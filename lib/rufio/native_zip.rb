# frozen_string_literal: true

require 'fiddle'
require_relative 'native_scanner'
require_relative 'native_scanner_zig'

module Rufio
  # Zig 実装の ZIP データ処理（並列・GVL 外）。
  #
  # 安全性の検証・パスの決定・ディレクトリ作成・rename・権限と日時の設定は Ruby 側
  # （ZipExtractor / ZipWriter）が担い、ここではエントリ単位のデータ処理だけを行う。
  # - 展開: ZIP 内の指定範囲を読み、伸長し、宣言サイズと CRC-32 を検証して一時ファイルに書く
  # - 圧縮: ファイルを raw DEFLATE で一時ファイルに書き、CRC-32 とサイズを返す
  module NativeZip
    STATE_RUNNING = 1
    STATE_DONE = 2
    STATE_CANCELLED = 3
    POLL_INTERVAL = 0.005

    # タスクごとの結果コード（Zig 側 zip.zig の Status と一致させる）
    STATUS_OK = 0
    STATUS_CRC_MISMATCH = 1
    STATUS_SIZE_MISMATCH = 2
    STATUS_CORRUPT = 3
    STATUS_IO_ERROR = 4
    STATUS_CANCELLED = 5
    STATUS_TOO_LARGE = 6
    STATUS_PENDING = 255

    class << self
      def available?
        return false if ENV['RUFIO_NATIVE_ZIP'] == '0'

        NativeScannerZigFFI.zip_available?
      end
    end

    # 実行中のジョブ（展開・圧縮共通）
    class Job
      def initialize(handle, count)
        raise StandardError, 'Failed to start native ZIP job' if handle.zero?

        @handle = handle
        @count = count
        @done = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
        @total = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
      end

      # 完了まで待つ。progress には (処理済みバイト数, 合計バイト数) を渡す。
      # cancelled が true を返したらキャンセルを要求し、終了を待ってから戻る
      def wait(progress: nil, cancelled: nil)
        loop do
          state = NativeScannerZigFFI.core_zip_state(@handle)
          report(progress)
          return state unless state == STATE_RUNNING

          NativeScannerZigFFI.core_zip_cancel(@handle) if cancelled&.call
          sleep POLL_INTERVAL
        end
      end

      def status(index)
        NativeScannerZigFFI.core_zip_status(@handle, index)
      end

      def close
        return if @handle.zero?

        NativeScannerZigFFI.core_zip_destroy(@handle)
        @handle = 0
      end

      protected

      attr_reader :handle

      private

      def report(progress)
        return unless progress

        NativeScannerZigFFI.core_zip_progress(@handle, @done, @total)
        progress.call(@done[0, 8].unpack1('Q<'), @total[0, 8].unpack1('Q<'))
      end
    end

    # @param zip_path [String]
    # @param tasks [Array<Hash>] data_offset:, compressed_size:, size:, crc32:, method:, output: (一時ファイルのパス)
    def self.extract(zip_path, tasks, threads: 0)
      buffer = tasks.map do |task|
        output = task[:output].b
        [task[:data_offset], task[:compressed_size], task[:size], task[:crc32], task[:method], output.bytesize]
          .pack('Q<Q<Q<L<CL<') + output
      end.join
      path = zip_path.b
      Job.new(NativeScannerZigFFI.core_zip_extract_create(path, path.bytesize, buffer, buffer.bytesize, threads), tasks.length)
    end

    # 圧縮ジョブ
    class DeflateJob < Job
      # @return [Array(Integer, Integer, Integer, Integer)] status, crc32, 圧縮後サイズ, 元サイズ
      def result(index)
        crc = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
        compressed = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
        size = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
        status = NativeScannerZigFFI.core_zip_deflate_result(handle, index, crc, compressed, size)
        [status, crc[0, 4].unpack1('L<'), compressed[0, 8].unpack1('Q<'), size[0, 8].unpack1('Q<')]
      end
    end

    # @param tasks [Array<Hash>] source:, output: (一時ファイルのパス)
    def self.deflate(tasks, level:, threads: 0)
      buffer = tasks.map do |task|
        source = task[:source].b
        output = task[:output].b
        [source.bytesize].pack('L<') + source + [output.bytesize].pack('L<') + output
      end.join
      DeflateJob.new(NativeScannerZigFFI.core_zip_deflate_create(buffer, buffer.bytesize, level, threads), tasks.length)
    end
  end
end
