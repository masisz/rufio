# frozen_string_literal: true

require_relative 'lib/rufio/version'

Gem::Specification.new do |spec|
  spec.name = 'rufio'
  spec.version = Rufio::VERSION
  spec.authors = ['masisz']
  spec.email = ['masisz.1567@gmail.com']

  spec.summary = 'Ruby file manager'
  spec.description = 'A terminal-based file manager inspired by Yazi, written in Ruby with plugin support'
  spec.homepage = 'https://github.com/masisz/rufio'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.7.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/masisz/rufio'
  spec.metadata['changelog_uri'] = 'https://github.com/masisz/rufio/blob/main/CHANGELOG.md'

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.bindir = 'bin'
  spec.executables = spec.files.grep(%r{\Abin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'io-console', '~> 0.6'
  spec.add_dependency 'pastel', '~> 0.8'
  spec.add_dependency 'tty-cursor', '~> 0.7'
  spec.add_dependency 'tty-screen', '~> 0.8'

  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rubocop', '~> 1.21'
end
