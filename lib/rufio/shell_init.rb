# frozen_string_literal: true

module Rufio
  # `rufio --shell-init` が出力するシェル関数。
  # rufio は子プロセスなので親シェルの作業ディレクトリを変えられない。
  # T キーで終了した時に rufio が --choosedir のファイルへ書いたディレクトリへ、関数側で cd する。
  module ShellInit
    FUNCTION_NAME = 'rf'
    SHELLS = %w[bash zsh fish powershell].freeze

    class << self
      # OS とログインシェルから出力するシェルを決める。
      # Windows は PowerShell。ただし Git Bash など SHELL が設定された環境ではそのシェルに合わせる。
      def detect(platform: RUBY_PLATFORM, env: ENV)
        shell = env['SHELL'].to_s.split(%r{[/\\]}).last.to_s.sub(/\.exe\z/i, '')
        return shell if SHELLS.include?(shell)

        platform =~ /mswin|mingw/ ? 'powershell' : 'bash'
      end

      def script(shell)
        case shell
        when 'bash', 'zsh' then posix_script(shell)
        when 'fish' then fish_script
        when 'powershell', 'pwsh' then powershell_script
        else
          raise ArgumentError, "Unsupported shell: #{shell} (#{SHELLS.join(', ')})"
        end
      end

      private

      def posix_script(shell)
        <<~SH
          # rufio shell integration (#{shell})
          # Add to ~/.#{shell}rc:  eval "$(rufio --shell-init #{shell})"
          # Run `#{FUNCTION_NAME}` and press T to quit rufio and cd to the last directory.
          #{FUNCTION_NAME}() {
            local tmp dir
            tmp="$(mktemp -t rufio-cwd.XXXXXX)" || return
            command rufio --choosedir "$tmp" "$@"
            dir="$(cat -- "$tmp" 2>/dev/null)"
            rm -f -- "$tmp"
            if [ -n "$dir" ] && [ -d "$dir" ] && [ "$dir" != "$PWD" ]; then
              cd -- "$dir"
            fi
          }
        SH
      end

      def fish_script
        <<~FISH
          # rufio shell integration (fish)
          # Add to ~/.config/fish/config.fish:  rufio --shell-init fish | source
          # Run `#{FUNCTION_NAME}` and press T to quit rufio and cd to the last directory.
          function #{FUNCTION_NAME}
              set -l tmp (mktemp -t rufio-cwd.XXXXXX); or return
              command rufio --choosedir $tmp $argv
              set -l dir (cat -- $tmp 2>/dev/null)
              rm -f -- $tmp
              if test -n "$dir"; and test -d "$dir"; and test "$dir" != "$PWD"
                  cd -- $dir
              end
          end
        FISH
      end

      def powershell_script
        <<~PS1
          # rufio shell integration (PowerShell)
          # Add to $PROFILE:  Invoke-Expression (& rufio --shell-init powershell | Out-String)
          # Run `#{FUNCTION_NAME}` and press T to quit rufio and cd to the last directory.
          function #{FUNCTION_NAME} {
              $tmp = New-TemporaryFile
              try {
                  rufio --choosedir $tmp.FullName @args
                  $dir = Get-Content -LiteralPath $tmp.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                  if ($dir) { $dir = $dir.Trim() }
                  if ($dir -and (Test-Path -LiteralPath $dir -PathType Container)) {
                      Set-Location -LiteralPath $dir
                  }
              } finally {
                  Remove-Item -LiteralPath $tmp.FullName -ErrorAction SilentlyContinue
              }
          }
        PS1
      end
    end
  end
end
