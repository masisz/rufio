# CHANGELOG - rufio v0.7.0

**Release Date**: 2025-11-29

## 🚀 New Features

### Plugin System

- **Extensible Plugin Architecture**: rufio now supports a plugin system that allows users to add custom functionality
- **Two Plugin Locations**:
  - **Built-in Plugins** (`lib/rufio/plugins/*.rb`): Core plugins bundled with rufio
  - **User Plugins** (`~/.rufio/plugins/*.rb`): User-created plugins for custom extensions
- **Automatic Plugin Registration**: Plugins are automatically registered when inheriting from the `Plugin` base class
- **Dependency Management**: Plugins can declare gem dependencies using `requires` method
- **Plugin Configuration**: Enable/disable plugins via `~/.rufio/config.yml`
- **Graceful Error Handling**: Missing dependencies show warnings but don't prevent rufio from starting

### Plugin Base Class

- **Simple Plugin Creation**: Easy-to-use base class for creating plugins
- **Required Methods**:
  - `name`: Plugin name (required)
  - `description`: Plugin description (optional, default: "")
  - `version`: Plugin version (optional, default: "1.0.0")
  - `commands`: Command definitions (optional, default: {})
- **Dependency Declaration**: Use `requires 'gem_name'` to declare gem dependencies
- **Automatic Dependency Checking**: Dependencies are checked on plugin initialization
- **DependencyError**: Custom error class for missing dependencies

### Plugin Manager

- **Plugin Discovery**: Automatically loads plugins from built-in and user directories
- **Plugin Lifecycle Management**: Handles plugin loading, initialization, and error recovery
- **Configuration Integration**: Respects plugin enable/disable settings from config file
- **Error Isolation**: Plugin errors don't crash the application

### Plugin Configuration

- **YAML Configuration**: Configure plugins via `~/.rufio/config.yml`
- **Enable/Disable Control**: Fine-grained control over which plugins are active
- **Case-Insensitive Names**: Plugin names are matched case-insensitively
- **Default Behavior**: All plugins enabled by default if not specified in config

### Built-in Plugins

- **FileOperations Plugin**: Basic file operations (copy, move, delete)
  - No external dependencies
  - Stub implementation ready for future enhancements

## 🎨 UI/UX Improvements

### Documentation

- **Plugin System Documentation**: Comprehensive documentation added to README.md and README_EN.md
  - Plugin creation guides with examples
  - Simple plugin example (Hello plugin)
  - Plugin with external dependencies example (AI Helper)
  - Plugin distribution methods (GitHub Gist, GitHub Repository)
  - Plugin management instructions
  - Plugin key features explanation

## 📖 Documentation Updates

### README Updates

**Japanese Version (README.md)**:

- Added "Plugin System" to Features section
- New comprehensive "Plugin System" section including:
  - Plugin location explanation
  - Plugin creation methods with code examples
  - Plugin management (enable/disable via config.yml)
  - Plugin distribution methods
  - Plugin key features

**English Version (README_EN.md)**:

- Added "Plugin System" to Features section
- New comprehensive "Plugin System" section with:
  - Plugin locations
  - Creating plugins guide
  - Simple and advanced plugin examples
  - Plugin management instructions
  - Distribution methods
  - Key features documentation

## 🔧 Technical Improvements

### Architecture

- **Plugin Module**: New `Rufio::Plugins` module for organizing plugins
- **Plugin Base Class** (`lib/rufio/plugin.rb`):
  - `Plugin.inherited`: Auto-registration mechanism
  - `Plugin.requires`: Dependency declaration
  - `Plugin.required_gems`: Dependency listing
  - `check_dependencies!`: Automatic dependency verification
  - `DependencyError`: Custom exception for missing dependencies

- **PluginManager Class** (`lib/rufio/plugin_manager.rb`):
  - `PluginManager.plugins`: Registry of all plugin classes
  - `PluginManager.register`: Plugin registration
  - `PluginManager.load_all`: Load all plugins from both locations
  - `PluginManager.enabled_plugins`: Get list of active plugin instances
  - `load_builtin_plugins`: Load from `lib/rufio/plugins/`
  - `load_user_plugins`: Load from `~/.rufio/plugins/`

- **PluginConfig Class** (`lib/rufio/plugin_config.rb`):
  - `PluginConfig.load`: Load configuration from `~/.rufio/config.yml`
  - `PluginConfig.plugin_enabled?`: Check if plugin is enabled
  - Case-insensitive plugin name matching
  - Graceful handling of missing config files

### Integration

- **Main Library Integration**: Plugin system integrated into `lib/rufio.rb`
- **Automatic Loading**: Plugins loaded at rufio startup
- **Error Recovery**: Plugin failures don't prevent application startup

## 🧪 Testing

### Test-Driven Development

- **TDD Approach**: All plugin system features developed using TDD methodology
- **Comprehensive Test Coverage**: Full test suite for plugin system

### New Tests Added

- **Plugin Base Class Tests** (`test/test_plugin.rb`):
  - Plugin registration tests
  - Dependency declaration tests
  - Dependency checking tests
  - Method override tests
  - DependencyError tests

- **PluginManager Tests** (`test/test_plugin_manager.rb`):
  - Plugin registration tests
  - Built-in plugin loading tests
  - User plugin loading tests
  - Enabled plugins filtering tests
  - Error handling tests
  - Missing dependency handling tests

- **PluginConfig Tests** (`test/test_plugin_config.rb`):
  - Configuration file loading tests
  - Plugin enable/disable tests
  - Case-insensitive name matching tests
  - Default behavior tests
  - Malformed YAML handling tests

- **FileOperations Plugin Tests** (`test/test_plugins_file_operations.rb`):
  - Plugin existence tests
  - Command registration tests
  - Dependency verification tests

## 📦 Dependencies

### No New Required Dependencies

- Plugin system uses only Ruby standard library
- External gem dependencies are optional and plugin-specific

### Dependency Management

- **Gem::Specification**: Used for dependency checking (Ruby standard library)
- **YAML**: Used for configuration file parsing (Ruby standard library)

## 🔄 Compatibility

### Backward Compatibility

- **No Breaking Changes**: All existing rufio features work as before
- **Optional Feature**: Plugin system is completely optional
- **Configuration File Compatibility**: Existing config files remain valid
- **No Impact on Core Functionality**: Plugins don't affect core file manager operations

### Platform Support

- **macOS**: Full support
- **Linux**: Full support
- **Windows**: Full support

## ⚡ Performance

### Optimizations

- **Lazy Loading**: Plugins loaded only when needed
- **Error Isolation**: Plugin errors don't impact core performance
- **Minimal Overhead**: Plugin system adds negligible startup time

## 🐛 Bug Fixes

### Fixed Issues

- **Test Compatibility**: Fixed test suite for Ruby 3.4+ compatibility
  - Replaced `assert_nothing_raised` with direct assertions
  - Fixed module constant cleanup in tests
  - Improved test isolation

## 🔮 Future Plans

### Planned for Next Version

- **Plugin API Extensions**: Additional hooks and events for plugins
- **Plugin Repository**: Central repository for sharing rufio plugins
- **Plugin CLI Commands**: Built-in commands for managing plugins
- **Plugin Dependencies**: Support for inter-plugin dependencies
- **Plugin Templates**: Scaffolding tools for creating new plugins

## 📝 Usage Examples

### Creating a Simple Plugin

```ruby
# ~/.rufio/plugins/hello.rb
module Rufio
  module Plugins
    class Hello < Plugin
      def name
        'Hello'
      end

      def description
        'Simple greeting plugin'
      end

      def commands
        {
          hello: method(:say_hello)
        }
      end

      private

      def say_hello
        puts "Hello from rufio!"
      end
    end
  end
end
```

### Installing a Plugin

```bash
# Create plugins directory
mkdir -p ~/.rufio/plugins

# Download plugin from GitHub Gist
curl -o ~/.rufio/plugins/my_plugin.rb [RAW_URL]

# Launch rufio (plugin will be loaded automatically)
rufio
```

### Configuring Plugins

```yaml
# ~/.rufio/config.yml
plugins:
  fileoperations:
    enabled: true
  hello:
    enabled: true
  my_custom_plugin:
    enabled: false
```

## 🙏 Acknowledgments

Main contributions in this version:

- **Test-Driven Development**: Complete TDD approach for plugin system
- **Ruby Standard Library**: Extensive use of built-in modules for reliability
- **Community Feedback**: Design inspired by popular plugin systems

---

**Note**: This version introduces the foundational plugin system for rufio. The plugin API is stable but may be extended in future versions based on community feedback.

**GitHub Issues**: [https://github.com/masisz/rufio/issues](https://github.com/masisz/rufio/issues)
