# frozen_string_literal: true

require 'shellwords'

module Rufio
  # 検出対象の拡張子・名前解決・ファイル実行方法を一か所で定義する。
  module ScriptFile
    # .sh は shebang を尊重して直接実行する。PowerShell は既存の pwsh を維持する。
    INTERPRETERS = {
      '.sh' => nil, '.rb' => 'ruby', '.py' => 'python3', '.pl' => 'perl',
      '.js' => 'node', '.ts' => 'ts-node', '.ps1' => 'pwsh'
    }.freeze
    EXTENSIONS = INTERPRETERS.keys.freeze

    def self.supported?(path)
      INTERPRETERS.key?(File.extname(path).downcase)
    end

    def self.executable?(path)
      supported?(path) || File.executable?(path)
    end

    def self.find(scripts, name)
      exact = scripts.find { |script| script[:name] == name }
      return exact if exact

      EXTENSIONS.each do |extension|
        match = scripts.find { |script| script[:name] == "#{name}#{extension}" }
        return match if match
      end
      nil
    end

    def self.complete(scripts, prefix)
      scripts.map { |script| script[:name] }.select { |name| name.start_with?(prefix) }.uniq.sort
    end

    def self.command(path, args: nil)
      interpreter = INTERPRETERS[File.extname(path).downcase]
      command = [interpreter, path.shellescape].compact.join(' ')
      args && !args.empty? ? "#{command} #{args}" : command
    end
  end
end
