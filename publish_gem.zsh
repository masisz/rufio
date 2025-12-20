#!/bin/zsh

# Gem Build & Push Script
# Usage: ./publish_gem.zsh [version]

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the correct directory
if [[ ! -f "rufio.gemspec" ]]; then
    print_error "rufio.gemspec not found. Please run this script from the project root directory."
    exit 1
fi

# Get current version from version.rb
CURRENT_VERSION=$(ruby -r ./lib/rufio/version -e "puts Rufio::VERSION")
print_status "Current version: $CURRENT_VERSION"

# Use provided version or current version
VERSION=${1:-$CURRENT_VERSION}
print_status "Publishing version: $VERSION"

# Confirm before proceeding
echo
read "REPLY?Do you want to proceed with publishing version $VERSION? (y/N): "
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Aborted by user."
    exit 0
fi

echo
print_status "Starting gem publication process..."

# Step 1: Run tests
print_status "Running tests..."
if ! bundle exec rake test; then
    print_error "Tests failed. Aborting publication."
    exit 1
fi
print_success "All tests passed!"

# Step 2: Clean up old gem files
print_status "Cleaning up old gem files..."
rm -f *.gem
print_success "Cleanup completed."

# Step 3: Build gem
print_status "Building gem..."
if ! bundle exec gem build rufio.gemspec; then
    print_error "Gem build failed."
    exit 1
fi

# Find the built gem file
GEM_FILE=$(ls rufio-*.gem | head -n 1)
if [[ -z "$GEM_FILE" ]]; then
    print_error "No gem file found after build."
    exit 1
fi

print_success "Gem built successfully: $GEM_FILE"

# Step 4: Verify gem contents (optional)
print_status "Gem contents:"
gem contents $GEM_FILE | head -10
echo "..."

# Step 5: Final confirmation
echo
read "REPLY?Push $GEM_FILE to RubyGems? (y/N): "
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Gem build completed but not published."
    print_status "You can manually push later with: gem push $GEM_FILE"
    exit 0
fi

# Step 6: Push to RubyGems
print_status "Pushing gem to RubyGems..."
if ! gem push $GEM_FILE; then
    print_error "Gem push failed."
    exit 1
fi

print_success "Gem published successfully!"

# Step 7: Create git tag if version was provided
if [[ -n "$1" ]]; then
    print_status "Creating git tag v$VERSION..."
    if git tag "v$VERSION" 2>/dev/null; then
        print_success "Tag v$VERSION created."
        read "REPLY?Push tag to remote? (y/N): "
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git push origin "v$VERSION"
            print_success "Tag pushed to remote."
        fi
    else
        print_warning "Tag v$VERSION already exists or failed to create."
    fi
fi

# Step 8: Cleanup
print_status "Cleaning up gem file..."
rm -f $GEM_FILE

echo
print_success "Publication completed!"
print_status "Gem should be available at: https://rubygems.org/gems/rufio"
print_status "Install with: gem install rufio"
