# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'
require_relative 'lib/rufio/version'

# Test task
Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/test_*.rb']
end

# Default task
task default: :test

# Zig native library tasks
namespace :native do
  desc 'Cross-compile the Zig library for every bundled platform (requires zig)'
  task :build do
    sh 'make -C lib_zig/rufio_native dist'
  end

  desc 'Verify bundled Zig binaries for macOS, Linux and Windows'
  task :check do
    ruby '-I test -I lib test/test_native_platform_binaries.rb'
  end
end

# Gem build and push tasks
namespace :gem do
  desc 'Build the gem file'
  task :build => 'native:check' do
    puts "Building rufio v#{Rufio::VERSION}..."
    
    # Clean old gem files
    FileUtils.rm_f(Dir.glob('*.gem'))
    
    # Build the gem
    result = system('gem build rufio.gemspec')
    
    if result
      gem_file = "rufio-#{Rufio::VERSION}.gem"
      puts "✅ Successfully built #{gem_file}"
    else
      puts "❌ Failed to build gem"
      exit 1
    end
  end

  desc 'Push the gem to RubyGems.org'
  task :push => :build do
    gem_file = "rufio-#{Rufio::VERSION}.gem"
    
    unless File.exist?(gem_file)
      puts "❌ Gem file not found: #{gem_file}"
      exit 1
    end
    
    puts "Pushing #{gem_file} to RubyGems.org..."
    
    result = system("gem push #{gem_file}")
    
    if result
      puts "✅ Successfully pushed #{gem_file} to RubyGems.org"
      puts "🎉 rufio v#{Rufio::VERSION} is now available!"
      puts "📦 Install with: gem install rufio"
    else
      puts "❌ Failed to push gem to RubyGems.org"
      exit 1
    end
  end

  desc 'Check if current version already exists on RubyGems.org'
  task :check_version do
    puts "Checking if version #{Rufio::VERSION} exists on RubyGems.org..."
    
    result = system("gem list rufio --remote --exact --all | grep '#{Rufio::VERSION}'", out: File::NULL, err: File::NULL)
    
    if result
      puts "⚠️  Version #{Rufio::VERSION} already exists on RubyGems.org"
      puts "💡 Please update the version in lib/rufio/version.rb before publishing"
      exit 1
    else
      puts "✅ Version #{Rufio::VERSION} is available for publishing"
    end
  end

  desc 'Clean built gem files'
  task :clean do
    puts "Cleaning gem files..."
    removed_files = Dir.glob('*.gem')
    FileUtils.rm_f(removed_files)
    
    if removed_files.any?
      puts "🗑️  Removed: #{removed_files.join(', ')}"
    else
      puts "✨ No gem files to clean"
    end
  end

  desc 'Build and publish gem (with version check)'
  task :publish => [:check_version, :test, :push] do
    puts "🚀 Gem publishing completed successfully!"
  end
end

# Release tasks
namespace :release do
  desc 'Tag the current version in git'
  task :tag do
    version = "v#{Rufio::VERSION}"
    
    puts "Creating git tag #{version}..."
    
    # Check if tag already exists
    if system("git tag -l | grep -q '^#{version}$'", out: File::NULL, err: File::NULL)
      puts "⚠️  Tag #{version} already exists"
      exit 1
    end
    
    # Create and push tag
    system("git tag #{version}")
    system("git push origin #{version}")
    
    puts "✅ Created and pushed tag #{version}"
  end

  desc 'Prepare release (tag + gem publish)'
  task :prepare => ['gem:publish', :tag] do
    puts "🎉 Release v#{Rufio::VERSION} completed!"
    puts "📋 Don't forget to:"
    puts "   - Update CHANGELOG.md"
    puts "   - Create GitHub release from tag"
    puts "   - Announce the release"
  end
end

# Utility tasks
desc 'Display current version'
task :version do
  puts "rufio v#{Rufio::VERSION}"
end

desc 'Run simple test for basic functionality'
task :simple_test do
  puts "Running simple functionality test..."
  result = system('ruby test/simple_test.rb')
  
  if result
    puts "✅ Simple test passed"
  else
    puts "❌ Simple test failed"
    exit 1
  end
end

desc 'Run bookmark tests'
task :test_bookmark do
  puts "Running bookmark functionality test..."
  result = system('ruby test/test_bookmark_simple.rb')
  
  if result
    puts "✅ Bookmark tests passed"
  else
    puts "❌ Bookmark tests failed"
    exit 1
  end
end