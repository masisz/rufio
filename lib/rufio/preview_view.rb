# frozen_string_literal: true

require_relative 'preview_registry'
require_relative 'table_source'
require_relative 'config_loader'
require_relative 'clipboard'

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

    def table?
      false
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
      target = copy_target
      if target.nil? || target.to_s.empty?
        notice('nothing to copy')
        return true
      end

      method = Clipboard.copy(target)
      notice(method ? "copied (#{method})" : 'clipboard unavailable')
      true
    end
  end

  # 従来のテキスト／コードプレビュー（行単位のスクロールのみ）
  class TextPreviewView < PreviewView
    PAGE_ROWS = 20

    attr_reader :row_offset

    def initialize(path: nil)
      super
      @row_offset = 0
    end

    def reset
      @row_offset = 0
      clear_notice
      true
    end

    def handle_key(key)
      case key
      when 'j', "\e[B" then scroll(1)
      when 'k', "\e[A" then scroll(-1)
      when "\x04" then page(1)   # Ctrl+D
      when "\x15" then page(-1)  # Ctrl+U
      else super
      end
    end

    def status_line
      notice_text || BACK_HINT
    end

    def scroll(delta)
      clear_notice
      @row_offset = [@row_offset + delta, 0].max
      true
    end

    def page(delta)
      scroll(delta * PAGE_ROWS)
    end
  end
end

require_relative 'table_preview_view'
