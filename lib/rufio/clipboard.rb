# frozen_string_literal: true

require 'base64'
require 'rbconfig'
require_relative 'config_loader'
require_relative 'command_locator'

module Rufio
  # クリップボードへのコピー。
  #
  # OS のコマンド（pbcopy / clip / wl-copy / xclip / xsel）を優先し、見つからなければ
  # OSC 52 で端末に渡す。OSC 52 は SSH 越しでも届く代わりに、端末が対応しているかを
  # 知る方法がない（成否が返らない）ため、どの手段を使ったかを呼び出し側で表示する。
  #
  # コマンドはシェルを経由せず argv で起動する（SECURITY.md の方針）。
  module Clipboard
    # コピーできる最大サイズ
    MAX_BYTES = 100 * 1024
    # OSC 52 で多くの端末が受け取れる上限の目安
    OSC52_MAX_BYTES = 74_994

    Candidate = Struct.new(:name, :argv, keyword_init: true)

    class << self
      # @param text [String] コピーする文字列
      # @return [Symbol, false] 使った手段（:pbcopy / :xclip / :osc52 ...）、失敗なら false
      def copy(text, out: $stdout)
        return false if text.nil?

        payload = text.to_s
        return false if payload.empty? || payload.bytesize > MAX_BYTES

        candidate = command_candidate
        return candidate.name if candidate && run_command(candidate.argv, payload)

        osc52(payload, out: out) ? :osc52 : false
      end

      # rufio -c（ヘルスチェック）用。使えそうな手段の名前
      # @return [Symbol] コマンドが見つからなければ :osc52
      def available_method
        command_candidate&.name || :osc52
      end

      # 見つかったコマンドの argv（ヘルスチェックの表示用）
      def available_command
        command_candidate&.argv
      end

      # 設定や環境変数を読み直す（テスト用）
      def reset!
        @command_candidate = nil
        @resolved = false
        CommandLocator.reset!
      end

      private

      def command_candidate
        return @command_candidate if @resolved

        @resolved = true
        @command_candidate = candidates.find { |candidate| command_available?(candidate.argv.first) }
      end

      def candidates
        [configured_candidate, *platform_candidates].compact
      end

      # config.rb の CLIPBOARD_COMMAND（文字列または argv 配列）
      def configured_candidate
        value = ConfigLoader.clipboard_command
        return nil if value.nil?

        argv = (value.is_a?(Array) ? value : [value]).map(&:to_s).reject(&:empty?)
        return nil if argv.empty?

        Candidate.new(name: :configured, argv: argv)
      end

      def platform_candidates
        case RbConfig::CONFIG['host_os']
        when /darwin/
          [Candidate.new(name: :pbcopy, argv: ['pbcopy'])]
        when /mswin|mingw|cygwin/
          [
            Candidate.new(name: :clip, argv: ['clip']),
            Candidate.new(name: :set_clipboard,
                          argv: ['powershell', '-NoProfile', '-Command', '$input | Set-Clipboard'])
          ]
        else
          unix_candidates
        end
      end

      # Wayland / X11 のセッションがあるときだけコマンドを試す。
      # SSH 越し（DISPLAY なし）では OSC 52 に任せる。
      def unix_candidates
        list = []
        list << Candidate.new(name: :wl_copy, argv: ['wl-copy']) if env?('WAYLAND_DISPLAY')
        if env?('DISPLAY')
          list << Candidate.new(name: :xclip, argv: ['xclip', '-selection', 'clipboard'])
          list << Candidate.new(name: :xsel, argv: ['xsel', '--clipboard', '--input'])
        end
        list
      end

      def env?(name)
        value = ENV[name]
        !value.nil? && !value.empty?
      end

      def command_available?(name)
        CommandLocator.available?(name)
      end

      def run_command(argv, text)
        IO.popen(argv, 'w') { |io| io.write(text) }
        status = Process.last_status
        status.nil? || status.success?
      rescue SystemCallError, IOError
        false
      end

      # OSC 52。tmux / screen の中では DCS パススルーで包む必要がある。
      def osc52(text, out: $stdout)
        sequence = "\e]52;c;#{Base64.strict_encode64(text)}\a"
        return false if sequence.bytesize > OSC52_MAX_BYTES

        out.write(wrap_for_multiplexer(sequence))
        out.flush
        true
      rescue SystemCallError, IOError
        false
      end

      def wrap_for_multiplexer(sequence)
        if env?('TMUX')
          # tmux 側は set-clipboard on が必要
          "\ePtmux;#{sequence.gsub("\e", "\e\e")}\e\\"
        elsif ENV['TERM'].to_s.start_with?('screen')
          "\eP#{sequence.gsub("\e", "\e\e")}\e\\"
        else
          sequence
        end
      end
    end
  end
end
