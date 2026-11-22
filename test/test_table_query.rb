# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

# 表プレビューの `/` で入力する絞り込み DSL。
#
#   price > 100, name a%   →  WHERE price > 100 AND name LIKE 'a%'
#
# SQLite では WHERE 句に組み立てて SQL を実行し、CSV / Excel では同じ条件を
# Ruby 側で行に当てる。ここでは解析と Ruby 側の判定を確認する。
class TestTableQuery < Minitest::Test
  COLUMNS = %w[name price stock note].freeze

  def parse(text, columns = COLUMNS)
    Rufio::TableQuery.parse(text, columns)
  end

  # === 解析 ===

  def test_blank_input_is_not_a_query
    assert_nil parse('')
    assert_nil parse('   ')
    assert_nil parse(nil)
  end

  def test_a_comparison_keeps_its_operator
    query = parse('price > 100')

    assert_equal 1, query.conditions.length
    condition = query.conditions.first
    assert_equal 'price', condition.column
    assert_equal '>', condition.operator
    assert_equal '100', condition.value
  end

  def test_every_comparison_operator_is_recognised
    %w[= != <> >= <= > <].each do |operator|
      condition = parse("price #{operator} 100").conditions.first
      assert_equal operator, condition.operator, operator
      assert_equal '100', condition.value, operator
    end
  end

  def test_an_operator_without_spaces_is_recognised
    condition = parse('price>=100').conditions.first

    assert_equal 'price', condition.column
    assert_equal '>=', condition.operator
    assert_equal '100', condition.value
  end

  def test_a_value_with_a_wildcard_becomes_like
    condition = parse('name a%').conditions.first

    assert_equal 'name', condition.column
    assert_equal 'LIKE', condition.operator
    assert_equal 'a%', condition.value, 'ワイルドカードはそのまま使うこと'
  end

  def test_a_plain_value_matches_anywhere_in_the_column
    condition = parse('name apple').conditions.first

    assert_equal 'LIKE', condition.operator
    assert_equal '%apple%', condition.value
  end

  def test_several_conditions_are_split_on_commas
    query = parse('price > 100, name a%')

    assert_equal 2, query.conditions.length
    assert_equal %w[price name], query.conditions.map(&:column)
    assert_equal ['>', 'LIKE'], query.conditions.map(&:operator)
  end

  def test_a_term_without_a_column_searches_every_column
    condition = parse('apple').conditions.first

    assert_nil condition.column, '列を指定しなければ全列が対象'
    assert_equal 'LIKE', condition.operator
    assert_equal '%apple%', condition.value
  end

  def test_column_names_ignore_case
    assert_equal 'price', parse('PRICE > 100').conditions.first.column
  end

  def test_column_labels_can_be_used
    condition = parse('B > 100')

    assert_equal 'price', condition.conditions.first.column, '列ラベル（A, B, ...）も使えること'
  end

  def test_quoted_values_keep_their_commas_and_spaces
    query = parse(%(note "red, sweet"))

    assert_equal 1, query.conditions.length
    condition = query.conditions.first
    assert_equal 'note', condition.column
    assert_equal '%red, sweet%', condition.value
  end

  def test_a_quoted_like_pattern_is_used_as_is
    condition = parse("name 'a%'").conditions.first

    assert_equal 'a%', condition.value
  end

  def test_a_missing_value_is_an_error
    error = assert_raises(Rufio::TableQuery::Error) { parse('price >') }
    assert_includes error.message.downcase, 'value'
  end

  def test_the_input_is_kept_for_display
    assert_equal 'price > 100, name a%', parse('price > 100, name a%').to_s
  end

  # === Ruby 側の判定（CSV / Excel） ===

  def row(name, price, stock, note = '')
    [name, price, stock, note]
  end

  def test_comparisons_are_numeric_when_both_sides_are_numbers
    query = parse('price > 100')

    assert query.matches?(row('apple', '120', '30'), COLUMNS)
    refute query.matches?(row('mikan', '80', '8'), COLUMNS)
    # 文字列比較なら "80" > "100" になってしまう
    refute query.matches?(row('mikan', '80.5', '8'), COLUMNS)
    assert query.matches?(row('melon', '1000', '1'), COLUMNS)
  end

  def test_decimal_values_compare_numerically
    query = parse('price <= 150.5')

    assert query.matches?(row('a', '150.5', '1'), COLUMNS)
    refute query.matches?(row('b', '150.6', '1'), COLUMNS)
  end

  def test_equality_falls_back_to_a_string_match
    query = parse('name = apple')

    assert query.matches?(row('apple', '120', '30'), COLUMNS)
    refute query.matches?(row('melon', '120', '30'), COLUMNS)
  end

  def test_not_equal_accepts_both_spellings
    ['name != apple', 'name <> apple'].each do |text|
      query = parse(text)
      refute query.matches?(row('apple', '1', '1'), COLUMNS), text
      assert query.matches?(row('melon', '1', '1'), COLUMNS), text
    end
  end

  def test_like_matches_the_pattern_ignoring_case
    query = parse('name a%')

    assert query.matches?(row('Apple', '120', '30'), COLUMNS)
    refute query.matches?(row('banana', '80', '12'), COLUMNS)
  end

  def test_underscore_matches_one_character
    query = parse('name a__le')

    assert query.matches?(row('apple', '1', '1'), COLUMNS)
    refute query.matches?(row('ale', '1', '1'), COLUMNS)
  end

  def test_a_substring_match_ignores_case
    query = parse('name PPL')

    assert query.matches?(row('apple', '1', '1'), COLUMNS)
  end

  def test_a_keyword_matches_any_column
    query = parse('sweet')

    assert query.matches?(row('apple', '120', '30', 'red, sweet'), COLUMNS)
    assert query.matches?(row('sweet potato', '80', '3'), COLUMNS)
    refute query.matches?(row('melon', '300', '2', 'green'), COLUMNS)
  end

  def test_several_conditions_are_joined_with_and
    query = parse('price > 100, name a%')

    assert query.matches?(row('apple', '120', '30'), COLUMNS)
    refute query.matches?(row('apple', '80', '30'), COLUMNS), '片方でも外れたら一致しないこと'
    refute query.matches?(row('melon', '300', '2'), COLUMNS)
  end

  def test_a_missing_cell_does_not_match
    query = parse('note red')

    refute query.matches?(['apple', '120', '30'], COLUMNS)
    refute query.matches?(['apple', '120', '30', nil], COLUMNS)
  end

  def test_metacharacters_in_a_value_are_literal
    query = parse('note a.c')

    assert query.matches?(row('x', '1', '1', 'a.c'), COLUMNS)
    refute query.matches?(row('x', '1', '1', 'abc'), COLUMNS), '. は正規表現として扱わないこと'
  end
end
