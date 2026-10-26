# frozen_string_literal: true

require 'io/console'

module Rufio
  # ダイアログなどのブロッキングなキー入力の読み取り口。
  # Windows ではメインループ用の入力スレッドが常に STDIN.getch で待機しているため、
  # ダイアログが STDIN.getch を直接呼ぶと 1 キーずつ入力を奪い合い、2 回押さないと入力できない。
  # 入力キューが接続されている間はキューから読み、それ以外は STDIN.getch を使う。
  module KeyInput
    # Ruby 3.2+ は Queue#pop(timeout:) で正確に待機する（sleep ポーリングは
    # Windows のタイマー分解能 約15ms により遅延する）。それ以前はポーリング。
    QUEUE_POP_TIMEOUT_SUPPORTED = Queue.instance_method(:pop).parameters.any? { |_, n| n == :timeout }
    MULTIBYTE_TIMEOUT = 0.005

    class << self
      attr_reader :queue

      def attach(queue)
        @queue = queue
      end

      def detach
        @queue = nil
      end

      # 1 文字（マルチバイト対応）を読むまでブロックする
      def getch
        queue = @queue
        return STDIN.getch unless queue

        loop do
          char = build_char(queue.pop, queue)
          return char if char
        end
      end

      # キューからタイムアウト付きで Integer バイトを取り出す
      def pop_with_timeout(queue, timeout_sec)
        return queue.pop(timeout: timeout_sec) if QUEUE_POP_TIMEOUT_SUPPORTED

        deadline = Time.now + timeout_sec
        loop do
          begin
            return queue.pop(true)
          rescue ThreadError
            return nil if Time.now >= deadline

            sleep 0.001
          end
        end
      end

      # first_byte_int に続く UTF-8 の後続バイトをキューから読み、1 文字に組み立てる
      def build_char(first_byte_int, queue)
        remaining = case first_byte_int
                    when 0x00..0x7F then 0
                    when 0xC0..0xDF then 1
                    when 0xE0..0xEF then 2
                    when 0xF0..0xF7 then 3
                    else 0
                    end
        return first_byte_int.chr(Encoding::UTF_8) if remaining == 0

        buf = first_byte_int.chr(Encoding::BINARY)
        remaining.times do
          b = pop_with_timeout(queue, MULTIBYTE_TIMEOUT)
          return nil if b.nil?

          buf << b.chr(Encoding::BINARY)
        end
        result = buf.force_encoding(Encoding::UTF_8)
        result.valid_encoding? ? result : nil
      end
    end
  end
end
