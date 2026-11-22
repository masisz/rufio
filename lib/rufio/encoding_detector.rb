# frozen_string_literal: true

module Rufio
  # バイト列の文字コードを判定し、UTF-8 文字列に変換する。
  #
  # 判定順: BOM → UTF-8 → CP932 → EUC-JP → UTF-8（不正バイトは置換）
  # CP932 と EUC-JP はどちらも「読めてしまう」ことがあるため、CP932 を先に試し、
  # 結果が半角カタカナばかりになる場合だけ EUC-JP を採用するヒューリスティックを使う。
  # 誤判定は設定（TABLE_PREVIEW の encoding）で上書きできる。
  module EncodingDetector
    UTF8_BOM = "\xEF\xBB\xBF".b
    UTF16LE_BOM = "\xFF\xFE".b
    UTF16BE_BOM = "\xFE\xFF".b

    # 自動判定で試す日本語エンコーディング（CP932 を優先）
    CP932 = 'CP932'
    EUC_JP = 'EUC-JP'

    REPLACEMENT = '?'

    # CP932 として読んだ結果がこの割合を超えて半角カタカナなら EUC-JP を採用する
    HALFWIDTH_KATAKANA_RATIO = 0.5

    Result = Struct.new(:text, :encoding, :truncated, :replaced, keyword_init: true)

    class << self
      # 先頭 max_bytes までを読み、UTF-8 文字列に変換して返す。
      # 上限で切るときは多バイト文字を割らないよう「上限内の最後の改行」までで切る。
      #
      # @param path [String]
      # @param max_bytes [Integer]
      # @param encoding [String] 'auto' または明示的なエンコーディング名
      # @return [Result]
      def read_text(path, max_bytes:, encoding: 'auto')
        raw = File.binread(path, max_bytes + 1) || ''
        raw = raw.b
        truncated = raw.bytesize > max_bytes
        raw = cut_at_line_boundary(raw, max_bytes) if truncated

        result = decode(raw, encoding: encoding)
        result.truncated = truncated
        result
      end

      # @param raw [String] バイト列
      # @return [Result]
      def decode(raw, encoding: 'auto')
        raw = raw.to_s.dup.force_encoding(Encoding::BINARY)
        return decode_as(raw, encoding) unless auto?(encoding)

        decode_bom(raw) || decode_utf8(raw) || decode_japanese(raw) || decode_with_replacement(raw)
      end

      private

      def auto?(encoding)
        encoding.nil? || encoding.to_s.empty? || encoding.to_s.casecmp?('auto')
      end

      # 上限内の最後の改行までで切る（行指向データなので境界が自然に取れる）
      def cut_at_line_boundary(raw, max_bytes)
        head = raw.byteslice(0, max_bytes)
        index = head.rindex("\n".b)
        index ? head.byteslice(0, index + 1) : head
      end

      def decode_bom(raw)
        if raw.start_with?(UTF8_BOM)
          body = raw.byteslice(UTF8_BOM.bytesize, raw.bytesize - UTF8_BOM.bytesize) || ''
          decode_utf8(body)
        elsif raw.start_with?(UTF16LE_BOM)
          decode_utf16(raw, Encoding::UTF_16LE)
        elsif raw.start_with?(UTF16BE_BOM)
          decode_utf16(raw, Encoding::UTF_16BE)
        end
      end

      # UTF-16 は BOM を除いた偶数バイト長で変換する（改行位置で切ると奇数になりうる）
      def decode_utf16(raw, source)
        body = raw.byteslice(2, raw.bytesize - 2) || ''
        body = body.byteslice(0, body.bytesize - 1) if body.bytesize.odd?
        text = body.force_encoding(source)
                   .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: REPLACEMENT)
        Result.new(text: strip_bom(text), encoding: source.to_s, truncated: false, replaced: false)
      rescue EncodingError
        nil
      end

      def decode_utf8(raw)
        text = raw.dup.force_encoding(Encoding::UTF_8)
        return nil unless text.valid_encoding?

        Result.new(text: strip_bom(text), encoding: 'UTF-8', truncated: false, replaced: false)
      end

      def decode_japanese(raw)
        cp932 = decode_candidate(raw, CP932)
        euc_jp = decode_candidate(raw, EUC_JP)
        return euc_jp unless cp932
        return cp932 unless euc_jp

        halfwidth_katakana_ratio(cp932.text) > HALFWIDTH_KATAKANA_RATIO ? euc_jp : cp932
      end

      def decode_candidate(raw, name)
        source = raw.dup.force_encoding(name)
        return nil unless source.valid_encoding?

        Result.new(text: strip_bom(source.encode(Encoding::UTF_8)), encoding: name,
                   truncated: false, replaced: false)
      rescue ArgumentError, EncodingError
        nil
      end

      def decode_with_replacement(raw)
        text = raw.dup.force_encoding(Encoding::UTF_8)
                   .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: REPLACEMENT)
        Result.new(text: strip_bom(text), encoding: 'UTF-8', truncated: false, replaced: true)
      end

      # 明示指定されたエンコーディングで変換する。未知の名前なら自動判定に戻す。
      def decode_as(raw, name)
        text = raw.dup.force_encoding(name)
                   .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: REPLACEMENT)
        Result.new(text: strip_bom(text), encoding: name.to_s, truncated: false, replaced: false)
      rescue ArgumentError, EncodingError
        decode(raw, encoding: 'auto')
      end

      def halfwidth_katakana_ratio(text)
        return 0.0 if text.empty?

        count = 0
        total = 0
        text.each_char do |char|
          total += 1
          count += 1 if char.match?(/[｡-ﾟ]/)
        end
        total.zero? ? 0.0 : count.to_f / total
      end

      def strip_bom(text)
        text.start_with?("﻿") ? text.sub("﻿", '') : text
      end
    end
  end
end
