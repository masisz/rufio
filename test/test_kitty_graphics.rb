# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require_relative '../lib/rufio'

# Kitty グラフィックスプロトコルのシーケンス組み立て。
# ここは文字列を作るだけで IO を持たないため、出力をそのまま検証できる。
class TestKittyGraphics < Minitest::Test
  APC = "\e_G"
  ST = "\e\\"

  def payload(length)
    'x' * length
  end

  # APC ごとに [制御部, ペイロード] に分解する
  def chunks(sequence)
    sequence.scan(/\e_G([^;]*);([^\e]*)\e\\/)
  end

  # === 転送 ===

  def test_a_small_image_is_sent_in_one_chunk
    sequence = Rufio::KittyGraphics.transmit(id: 7, payload: 'hello', cols: 10, rows: 5)
    parts = chunks(sequence)

    assert_equal 1, parts.length
    control, data = parts.first
    assert_equal ['hello'].pack('m0'), data, 'ペイロードは Base64 にすること'
    assert_includes control, 'a=T'
    assert_includes control, 'i=7'
    assert_includes control, 'c=10'
    assert_includes control, 'r=5'
    assert_includes control, 'f=100', '既定は PNG 直送'
    assert_includes control, 't=d'
  end

  def test_omitting_cols_and_rows_keeps_native_aspect_ratio
    sequence = Rufio::KittyGraphics.transmit(id: 7, payload: 'hello', cols: nil, rows: nil)
    control, = chunks(sequence).first

    assert_includes control, 'a=T'
    refute_match(/(?:\A|,)c=/, control, 'cols を省略したら c= を付けないこと')
    refute_match(/(?:\A|,)r=/, control, 'rows を省略したら r= を付けないこと')
  end

  def test_the_cursor_is_not_moved_and_responses_are_suppressed
    control, = chunks(Rufio::KittyGraphics.transmit(id: 1, payload: 'a', cols: 1, rows: 1)).first

    assert_includes control, 'C=1', 'C=1 が無いとカーソルがずれて画面が崩れる'
    assert_includes control, 'q=2', '応答は入力ループに混ざるので抑止する'
  end

  def test_a_large_image_is_split_into_chunks
    raw = payload(4096 * 2 + 10)
    sequence = Rufio::KittyGraphics.transmit(id: 1, payload: raw, cols: 4, rows: 2, chunk: 4096)
    parts = chunks(sequence)

    assert_operator parts.length, :>, 1
    # 最初のチャンクだけが制御キーを持ち、残りは m だけ
    assert_includes parts.first[0], 'a=T'
    parts[1..].each { |control, _| assert_match(/\Am=[01]\z/, control) }
    # 継続は m=1、最後は m=0
    assert_equal ['m=1'] * (parts.length - 2) + ['m=0'], parts[1..].map(&:first)
    assert_includes parts.first[0], 'm=1'
    # ペイロードは分割しても元に戻る
    assert_equal [raw].pack('m0'), parts.map(&:last).join
    parts.each { |_, data| assert_operator data.bytesize, :<=, 4096 }
  end

  def test_raw_pixels_need_their_size
    sequence = Rufio::KittyGraphics.transmit(id: 2, payload: 'rgb', cols: 2, rows: 1,
                                             format: Rufio::KittyGraphics::FORMAT_RGB,
                                             pixels: [16, 8])
    control, = chunks(sequence).first

    assert_includes control, 'f=24'
    assert_includes control, 's=16'
    assert_includes control, 'v=8'
  end

  # === 位置 ===

  def test_place_at_moves_the_cursor_first_and_returns_home
    sequence = Rufio::KittyGraphics.place_at(row: 5, col: 3, id: 1, payload: 'a', cols: 2, rows: 2)

    assert sequence.start_with?("\e[5;3H"), 'カーソルを左上へ動かしてから送ること'
    assert sequence.end_with?("\e[H"), '送り終わったらカーソルを戻すこと'
    assert_includes sequence, 'a=T'
  end

  # === 削除 ===

  def test_delete_targets_one_image
    sequence = Rufio::KittyGraphics.delete(id: 9)

    assert_includes sequence, 'a=d'
    assert_includes sequence, 'd=i'
    assert_includes sequence, 'i=9'
    assert sequence.start_with?(APC)
    assert sequence.end_with?(ST)
  end

  def test_delete_all_clears_every_image
    sequence = Rufio::KittyGraphics.delete_all

    assert_includes sequence, 'a=d'
    assert_includes sequence, 'd=A'
    refute_includes sequence, 'i='
  end

  # === 対応判定用の問い合わせ ===

  def test_the_query_asks_about_one_pixel_and_expects_an_answer
    sequence = Rufio::KittyGraphics.query(id: 31)

    assert_includes sequence, 'a=q'
    assert_includes sequence, 'i=31'
    assert_includes sequence, 's=1'
    assert_includes sequence, 'v=1'
  end

  # === tmux パススルー ===

  def test_passthrough_doubles_the_escapes_for_tmux
    plain = Rufio::KittyGraphics.delete_all
    wrapped = Rufio::KittyGraphics.delete_all(passthrough: true)

    assert wrapped.start_with?("\ePtmux;"), 'tmux のパススルーで包むこと'
    assert wrapped.end_with?("\e\\")
    assert_includes wrapped, plain.gsub("\e", "\e\e"), 'ESC は二重にすること'
  end

  def test_passthrough_wraps_every_chunk
    raw = payload(4096 * 2)
    wrapped = Rufio::KittyGraphics.transmit(id: 1, payload: raw, cols: 1, rows: 1, passthrough: true)

    assert_equal wrapped.scan("\ePtmux;").length, wrapped.scan("\e\e_G").length,
                 'チャンクごとに包むこと'
  end

  # === セキュリティ ===

  def test_encoded_payload_rejects_escape_sequence_injection
    malicious = "AAAA\e\\\e]52;c;aGVsbG8=\a"
    assert_equal '', Rufio::KittyGraphics.transmit(id: 1, payload: malicious, encoded: true)
    assert_equal '', Rufio::KittyGraphics.place_at(row: 1, col: 1, id: 1, payload: malicious, encoded: true)
  end

  def test_query_sanitizes_image_id_as_integer
    sequence = Rufio::KittyGraphics.query(id: "31\e\\;injected")
    assert_includes sequence, 'i=31,'
    refute_includes sequence, 'injected'
  end
end
