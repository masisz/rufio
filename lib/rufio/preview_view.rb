# frozen_string_literal: true

require_relative 'preview_registry'
require_relative 'table_source'
require_relative 'config_loader'
require_relative 'clipboard'
require_relative 'search_prompt'

module Rufio
  # プレビューモード中の「見え方」と「キー操作」をまとめた層。
  #
  # プレビュー種別を増やすときは、このプロトコルを満たすクラスを足して
  # PreviewView.build が返すようにするだけでよい。NavigationController と
  # UIRenderer はこのプロトコルしか知らない。
  #
  #   row_offset   縦スクロール位置（先頭に表示するデータ行）
  #   reset        先頭に戻す（別のファイルを選び直したとき）
  #   handle_key   プレビューフォーカス中のキー。扱わなければ false
  #   scroll/page  マウスホイールなど、キー以外からのスクロール
  #   status_line  ヘッダ下の 1 行に出す情報
  #   copy_target  y でコピーする文字列（nil ならコピー対象なし）
  #   cursor       セルカーソル（持たない種別は nil）
  #   visible_rows= 描画側が毎フレーム伝える表示行数（検索の追従に使う）
  #
  # `/` の検索は種別ごとに意味が変わる（テキストはファイル内検索、表は行の絞り込み）。
  class PreviewView
    BACK_HINT = 'y: copy path  ESC: Back to files'

    attr_reader :path

    class << self
      # @param path [String] プレビュー対象
      # @return [PreviewView] 表として読めれば TablePreviewView、それ以外は TextPreviewView
      def build(path)
        document = load_table(path)
        document ? TablePreviewView.new(document, path: path) : TextPreviewView.new(path: path)
      rescue StandardError
        # プレビューのために操作を止めない。表として読めなければテキスト扱い
        TextPreviewView.new(path: path)
      end

      private

      def load_table(path)
        return nil unless PreviewRegistry.table?(path) && File.file?(path)

        settings = ConfigLoader.table_preview
        limits = TableSource::Limits.new(
          max_bytes: settings[:max_bytes],
          max_rows: settings[:max_rows],
          max_columns: settings[:max_columns]
        )
        # FilePreview と同じキャッシュを使うので、同じファイルを二度パースしない
        PreviewRegistry.load_table(path, limits: limits, options: {
                                     header: settings[:header],
                                     delimiter: settings[:delimiter],
                                     encoding: settings[:encoding]
                                   })
      rescue TableSource::ParseError
        nil
      end
    end

    def initialize(path: nil)
      @path = path
      @notice = nil
    end

    def row_offset
      0
    end

    # 先頭に戻す
    def reset
      false
    end

    # 種別ごとのキーを先に処理し、ここでは共通のキー（y: コピー）だけを扱う
    def handle_key(key)
      return false unless copy_key?(key)

      perform_copy
    end

    def scroll(_delta)
      false
    end

    def page(_delta)
      false
    end

    def status_line
      BACK_HINT
    end

    # y でコピーする文字列。表プレビューはセルの値、それ以外はファイルパス
    def copy_target
      @path && File.expand_path(@path)
    end

    def cursor
      nil
    end

    # 描画側が毎フレーム伝える表示行数（既定値のままでも破綻しないよう無視できる）
    def visible_rows=(_rows); end

    # `/` の検索語（検索していなければ nil）
    def search_query
      nil
    end

    def search_prompt_open?
      false
    end

    # 描画側が求めた一致行（折り返し後の行番号）
    def search_matches
      []
    end

    def current_match
      nil
    end

    def apply_matches(_indices); end

    def table?
      false
    end

    # 複数シートを持つ種別だけが 0 以外を返す
    def sheet_index
      0
    end

    protected

    # コピー結果などの短い通知。次の操作まで表示し続ける
    def notice_text
      @notice
    end

    def notice(text)
      @notice = text
    end

    def clear_notice
      @notice = nil
    end

    def copy_key?(key)
      key == ConfigLoader.keybinds[:copy_to_clipboard]
    end

    def perform_copy
      copy_text(copy_target)
    end

    # @param label [String, nil] 通知に出す対象名（"row" など）
    def copy_text(text, label: nil)
      if text.nil? || text.to_s.empty?
        notice('nothing to copy')
        return true
      end

      method = Clipboard.copy(text)
      notice(method ? "#{copied_label(text, label)} (#{method})" : 'clipboard unavailable')
      true
    end

    # グリッドは改行を空白に畳んで表示するため、コピーした内容が複数行なら
    # 画面の見た目と違うことが分かるよう行数を出す
    def copied_label(text, label)
      copied = ['copied', label].compact.join(' ')
      lines = text.to_s.sub(/[\r\n]+\z/, '').lines.length
      lines > 1 ? "#{copied}, #{lines} lines" : copied
    end
  end

  # 従来のテキスト／コードプレビュー（行単位のスクロール）と、`/` のファイル内検索。
  #
  # 一致行の位置は折り返し後の行番号で扱う。折り返しはペインの幅に依存するため、
  # 一致行を求めるのは描画側（UIRenderer）で、apply_matches / visible_rows= で受け取る。
  class TextPreviewView < PreviewView
    PAGE_ROWS = 20
    # 検索中でないときのヒント
    SCROLL_HINT = 'j/k: scroll  /: search  y: copy path  ESC: back'
    MATCH_HINT = 'n/N: next/prev  ESC: clear'
    # 一致行を画面に出すとき、上に残す行数
    MATCH_MARGIN = 2

    attr_reader :row_offset, :search_query, :search_matches

    def initialize(path: nil)
      super
      @row_offset = 0
      @visible_rows = PAGE_ROWS
      clear_search
    end

    def reset
      @row_offset = 0
      clear_search
      clear_notice
      true
    end

    def visible_rows=(rows)
      @visible_rows = [rows.to_i, 1].max
    end

    def search_prompt_open?
      !@prompt.nil?
    end

    # 現在の一致行（折り返し後の行番号）。一致がなければ nil
    def current_match
      @search_matches[@match_index]
    end

    # 描画側が求めた一致行を受け取る。入力直後は現在位置以降の最初の一致へ飛ぶ
    def apply_matches(indices)
      @search_matches = Array(indices)
      if @search_matches.empty?
        @match_index = 0
        @pending_jump = false
        return
      end

      if @pending_jump
        @pending_jump = false
        @match_index = @search_matches.index { |index| index >= @row_offset } || 0
      end
      @match_index = @match_index.clamp(0, @search_matches.length - 1)
      ensure_match_visible
    end

    def handle_key(key)
      return handle_prompt_key(key) if search_prompt_open?
      return open_search_prompt if key == ConfigLoader.keybinds[:search]
      return next_match(1) if key == 'n' && searching?
      return next_match(-1) if key == 'N' && searching?
      return clear_search if key == "\e" && searching?

      case key
      when 'j', "\e[B" then scroll(1)
      when 'k', "\e[A" then scroll(-1)
      when "\x04" then page(1)   # Ctrl+D
      when "\x15" then page(-1)  # Ctrl+U
      else super
      end
    end

    # 入力中は `/query_`、確定後は一致件数と操作ヒントを出す
    def status_line
      return "/#{@prompt.query}_" if search_prompt_open?
      return notice_text if notice_text
      return SCROLL_HINT unless searching?

      found = @search_matches.empty? ? 'no matches' : "#{@match_index + 1}/#{@search_matches.length}"
      ["\"#{@search_query}\"  #{found}", MATCH_HINT].join('  |  ')
    end

    def scroll(delta)
      clear_notice
      @row_offset = [@row_offset + delta, 0].max
      true
    end

    def page(delta)
      scroll(delta * PAGE_ROWS)
    end

    private

    def searching?
      !@search_query.nil?
    end

    def open_search_prompt
      clear_notice
      @offset_before_search = @row_offset
      @prompt = SearchPrompt.new
      @search_query = ''
      @search_matches = []
      @match_index = 0
      @pending_jump = true
      true
    end

    # 入力中のキーはすべて入力欄で扱う（スクロールには使わない）
    def handle_prompt_key(key)
      case @prompt.handle_key(key)
      when :changed
        @search_query = @prompt.query
        @pending_jump = true
      when :submitted
        @prompt = nil
        clear_search if @search_query.to_s.empty?
      when :cancelled
        @prompt = nil
        @row_offset = @offset_before_search || @row_offset
        clear_search
      end
      true
    end

    def clear_search
      @prompt = nil
      @search_query = nil
      @search_matches = []
      @match_index = 0
      @pending_jump = false
      true
    end

    # n / N: 次 / 前の一致へ。端では反対側へ回る
    def next_match(step)
      return true if @search_matches.empty?

      @match_index = (@match_index + step) % @search_matches.length
      ensure_match_visible
      true
    end

    # 一致行が画面の外なら、少し上に余白を残して表示する
    def ensure_match_visible
      match = current_match
      return if match.nil?
      return if match >= @row_offset && match < @row_offset + @visible_rows

      @row_offset = [match - MATCH_MARGIN, 0].max
    end
  end
end

require_relative 'table_preview_view'
