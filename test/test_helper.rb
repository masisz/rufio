# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "rufio"

require "minitest"
require "fileutils"
require "tmpdir"

# minitestのプラグインを無効化してRailsとの競合を回避
ENV['MT_PLUGINS'] = ""
ENV['NO_PLUGINS'] = "true"

# Ruby 4.0でObject#stubが削除されたため、ポリフィルを提供
# 参考: https://github.com/ruby/ruby/pull/6991
class Object
  # 一時的にメソッドをスタブ化する
  # @param name [Symbol] スタブ化するメソッド名
  # @param val_or_callable [Object, Proc] 置き換える値またはcallable
  # @yield ブロック内でスタブが有効
  # @return [Object] ブロックの戻り値
  def stub(name, val_or_callable)
    new_name = "__minitest_stub__#{name}"

    # 元のメソッドを退避（存在する場合）
    has_original = respond_to?(name, true)
    if has_original
      metaclass = singleton_class
      metaclass.send(:alias_method, new_name, name)
    end

    # スタブメソッドを定義
    metaclass = singleton_class
    metaclass.send(:define_method, name) do |*args, **kwargs, &block|
      if val_or_callable.respond_to?(:call)
        if kwargs.empty?
          val_or_callable.call(*args, &block)
        else
          val_or_callable.call(*args, **kwargs, &block)
        end
      else
        val_or_callable
      end
    end

    begin
      yield
    ensure
      # 元のメソッドを復元
      metaclass = singleton_class
      if has_original
        metaclass.send(:alias_method, name, new_name)
        metaclass.send(:remove_method, new_name)
      else
        metaclass.send(:remove_method, name)
      end
    end
  end
end

# 手動でminitestを実行
Minitest.run if __FILE__ == $0