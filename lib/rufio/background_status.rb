# frozen_string_literal: true

module Rufio
  # 完了通知とフッターランプで共有する実行状態・表示期限。
  # 描画側は message を読むだけにし、状態の更新はメインループで行う。
  class BackgroundStatus
    POLL_INTERVAL = 0.1
    DISPLAY_DURATION = 3.0

    attr_reader :message

    def initialize(now: Time.now)
      @last_poll = now
      @running = false
      @message = nil
      @expires_at = nil
    end

    # 描画に関わる状態が変化した場合だけ true を返す。
    def update(executor, now: Time.now)
      changed = expire(now)
      running = executor ? executor.running? : false
      if running != @running
        @running = running
        changed = true
      end

      if executor && now - @last_poll > POLL_INTERVAL
        @last_poll = now
        if (message = executor.consume_completion_message)
          @message = message
          @expires_at = now + DISPLAY_DURATION
          changed = true
        end
      end
      changed
    end

    private

    def expire(now)
      return false unless @expires_at && now >= @expires_at

      @message = nil
      @expires_at = nil
      true
    end
  end
end
