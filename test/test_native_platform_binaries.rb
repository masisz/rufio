# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'rubygems'

# Gem に同梱する各プラットフォーム向け Zig バイナリの検証
class TestNativePlatformBinaries < Minitest::Test
  FFI = Rufio::NativeScannerZigFFI
  NATIVE_DIR = File.expand_path('../lib/rufio/native', __dir__)

  # [プラットフォーム, 形式, CPU]
  EXPECTED = {
    'aarch64-macos' => [:macho, :aarch64],
    'x86_64-macos' => [:macho, :x86_64],
    'x86_64-linux-gnu' => [:elf, :x86_64],
    'aarch64-linux-gnu' => [:elf, :aarch64],
    'x86_64-linux-musl' => [:elf, :x86_64],
    'aarch64-linux-musl' => [:elf, :aarch64],
    'x86_64-windows' => [:pe, :x86_64],
    'aarch64-windows' => [:pe, :aarch64]
  }.freeze

  REQUIRED_EXPORTS = %w[core_async_create core_async_get_attrs core_search_create core_search_drain
                        core_cache_create core_cache_destroy].freeze

  def test_platform_dir_detection
    assert_equal 'aarch64-macos', FFI.platform_dir('darwin23', 'arm64')
    assert_equal 'aarch64-macos', FFI.platform_dir('darwin24.1.0', 'aarch64')
    assert_equal 'x86_64-macos', FFI.platform_dir('darwin22', 'x86_64')
    assert_equal 'x86_64-linux-gnu', FFI.platform_dir('linux-gnu', 'x86_64')
    assert_equal 'aarch64-linux-gnu', FFI.platform_dir('linux', 'aarch64')
    assert_equal 'x86_64-linux-musl', FFI.platform_dir('linux-musl', 'x86_64')
    assert_equal 'aarch64-linux-musl', FFI.platform_dir('linux-musl', 'aarch64')
    assert_equal 'x86_64-windows', FFI.platform_dir('mingw32', 'x64')
    assert_equal 'x86_64-windows', FFI.platform_dir('mingw-ucrt', 'x86_64')
    assert_equal 'x86_64-windows', FFI.platform_dir('mswin64_140', 'x64')
    assert_equal 'aarch64-windows', FFI.platform_dir('mingw-ucrt', 'aarch64')
    assert_nil FFI.platform_dir('freebsd14', 'x86_64')
    assert_nil FFI.platform_dir('linux-gnu', 'i686')
    assert_nil FFI.platform_dir('cygwin', 'x86_64')
  end

  def test_library_file_names_per_os
    assert_equal File.join(NATIVE_DIR, 'aarch64-macos', 'librufio_zig.dylib'), FFI.library_path('darwin23', 'arm64')
    assert_equal File.join(NATIVE_DIR, 'x86_64-linux-gnu', 'librufio_zig.so'), FFI.library_path('linux-gnu', 'x86_64')
    assert_equal File.join(NATIVE_DIR, 'x86_64-windows', 'rufio_zig.dll'), FFI.library_path('mingw-ucrt', 'x64')
    assert_nil FFI.library_path('freebsd14', 'x86_64')
  end

  def test_supported_platforms_match_bundled_binaries
    assert_equal EXPECTED.keys.sort, FFI::PLATFORMS.keys.sort
  end

  def test_every_platform_binary_is_bundled_with_correct_format
    EXPECTED.each do |platform, (format, cpu)|
      path = File.join(NATIVE_DIR, platform, FFI::PLATFORMS.fetch(platform))
      assert File.file?(path), "missing binary for #{platform}: #{path}"
      bytes = File.binread(path)
      assert_equal [format, cpu], binary_signature(bytes), "wrong binary for #{platform}"
      REQUIRED_EXPORTS.each { |name| assert_includes bytes, name, "#{platform} lacks #{name}" }
    end
  end

  def test_gemspec_ships_all_platform_binaries
    spec = Dir.chdir(File.expand_path('..', __dir__)) { Gem::Specification.load('rufio.gemspec') }
    EXPECTED.each_key do |platform|
      assert_includes spec.files, "lib/rufio/native/#{platform}/#{FFI::PLATFORMS.fetch(platform)}"
    end
  end

  def test_current_platform_loads_bundled_library
    path = FFI.library_path
    skip "no bundled binary for #{RbConfig::CONFIG['host_os']} #{RbConfig::CONFIG['host_cpu']}" unless path

    assert_equal path, FFI.loaded_path
    assert FFI.available?
    assert FFI.search_available?
  end

  private

  def binary_signature(bytes)
    if bytes.byteslice(0, 4) == "\xCF\xFA\xED\xFE".b
      cputype = bytes.byteslice(4, 4).unpack1('L<')
      [:macho, { 0x0100000C => :aarch64, 0x01000007 => :x86_64 }[cputype]]
    elsif bytes.byteslice(0, 4) == "\x7FELF".b
      return [:elf32, nil] unless bytes.getbyte(4) == 2

      type, machine = bytes.byteslice(16, 4).unpack('S<S<')
      return [:elf_not_shared, nil] unless type == 3

      [:elf, { 62 => :x86_64, 183 => :aarch64 }[machine]]
    elsif bytes.byteslice(0, 2) == 'MZ'
      pe = bytes.byteslice(0x3C, 4).unpack1('L<')
      return [:not_pe, nil] unless bytes.byteslice(pe, 4) == "PE\0\0".b

      machine, = bytes.byteslice(pe + 4, 2).unpack('S<')
      characteristics = bytes.byteslice(pe + 22, 2).unpack1('S<')
      return [:pe_not_dll, nil] if (characteristics & 0x2000).zero?

      [:pe, { 0x8664 => :x86_64, 0xAA64 => :aarch64 }[machine]]
    else
      [:unknown, nil]
    end
  end
end
