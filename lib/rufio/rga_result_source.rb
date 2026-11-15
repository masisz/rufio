# frozen_string_literal: true

module Rufio
  # F の rga 出力（path:line:text）を FuzzySearchSession の候補として流す。
  # rga プロセスの起動・停止はプロデューサースレッド内で完結させる。
  class RgaResultSource
    BATCH_SIZE = 256
    POLL_INTERVAL = 0.05
    LINE_PATTERN = /\A(.+?):(\d+):/.freeze

    attr_reader :command

    def initialize(query, root, command: nil)
      @root = File.expand_path(root).freeze
      # "--" で検索語がオプション（--pre=コマンド 等）として解釈されるのを防ぐ
      @command = (command || ['rga', '--line-number', '--with-filename', '--no-heading',
                              '--color', 'never', '--', query, '.']).map { |part| part.to_s.dup.freeze }.freeze
    end

    def each_batch(cancelled:, on_error:)
      return if cancelled.call

      io = IO.popen(@command, 'rb', chdir: @root, err: File::NULL)
      buffer = +''.b
      batch = []
      until cancelled.call
        next unless IO.select([io], nil, nil, POLL_INTERVAL)

        begin
          buffer << io.readpartial(65_536)
        rescue EOFError
          break
        end
        while (newline = buffer.index("\n"))
          line = buffer.slice!(0, newline + 1)
          entry = parse(line)
          batch << entry if entry
          next if batch.length < BATCH_SIZE

          yield batch
          batch = []
        end
        unless batch.empty?
          yield batch
          batch = []
        end
      end
      return if cancelled.call

      entry = parse(buffer)
      yield [entry] if entry
      finished = true
    rescue SystemCallError, IOError => e
      on_error.call("#{@command.first}: #{e.message}")
    ensure
      stop(io, kill: !finished) if io
    end

    private

    def parse(raw)
      line = raw.chomp.delete_suffix("\r")
      match = line.match(LINE_PATTERN)
      return unless match

      relative = match[1].sub(%r{\A\.[/\\]}, '')
      rest = line.byteslice(match.end(0)..)
      text = "#{relative}:#{match[2]}:#{rest}".force_encoding(Encoding::UTF_8).scrub
      path = File.join(@root.b, relative).force_encoding(Encoding.default_external)
      { text: text, path: path, line_number: match[2].to_i }
    end

    # 途中で止めたときは rga を終了させてから回収する
    def stop(io, kill:)
      return if io.closed?

      if kill
        begin
          Process.kill(Gem.win_platform? ? 'KILL' : 'TERM', io.pid)
        rescue SystemCallError
          nil
        end
      end
      io.close
    rescue SystemCallError, IOError
      nil
    end
  end
end
