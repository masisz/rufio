# frozen_string_literal: true

module Rufio
  # 拡張子からインタープリタを解決するクラス
  class InterpreterResolver
    # デフォルトの拡張子とインタープリタのマッピング
    DEFAULT_EXTENSIONS = {
      ".rb" => "ruby",
      ".py" => "python3",
      ".sh" => "bash",
      ".js" => "node",
      ".pl" => "perl",
      ".lua" => "lua",
      ".ts" => "ts-node",
      ".php" => "php",
      ".ps1" => nil # プラットフォーム依存
    }.freeze

    class << self
      # 拡張子からインタープリタを解決する
      # @param extension [String] 拡張子（ドット付きまたはなし）
      # @return [String, nil] インタープリタ名、解決できない場合はnil
      def resolve(extension)
        # ドットで始まらない場合は追加
        ext = extension.start_with?(".") ? extension : ".#{extension}"
        ext = ext.downcase

        # PowerShellはプラットフォーム依存
        return resolve_powershell if ext == ".ps1"

        DEFAULT_EXTENSIONS[ext]
      end

      # ファイルパスから拡張子を取得してインタープリタを解決する
      # @param path [String] ファイルパス
      # @return [String, nil] インタープリタ名、解決できない場合はnil
      def resolve_from_path(path)
        ext = File.extname(path)
        return nil if ext.empty?

        resolve(ext)
      end

      # 全ての拡張子マッピングを取得する
      # @return [Hash] 拡張子とインタープリタのマッピング
      def all_extensions
        # PowerShellのプラットフォーム依存を解決した状態で返す
        DEFAULT_EXTENSIONS.merge(".ps1" => resolve_powershell)
      end

      # Windowsプラットフォームかどうか
      # @return [Boolean]
      def windows?
        RUBY_PLATFORM =~ /mingw|mswin|cygwin/ ? true : false
      end

      # macOSプラットフォームかどうか
      # @return [Boolean]
      def macos?
        RUBY_PLATFORM =~ /darwin/ ? true : false
      end

      # Linuxプラットフォームかどうか
      # @return [Boolean]
      def linux?
        RUBY_PLATFORM =~ /linux/ ? true : false
      end

      private

      # PowerShellのインタープリタを解決する
      # WindowsではpowershellとWindowsではpwsh
      # @return [String]
      def resolve_powershell
        windows? ? "powershell" : "pwsh"
      end
    end
  end
end
