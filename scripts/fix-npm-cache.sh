#!/bin/bash
# NPM Cache Fix Script
# Standalone script to fix npm cache ownership and cleanup issues

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() { echo -e "${BLUE}[NPM Cache Fix]${NC} $1"; }
log_success() { echo -e "${GREEN}[NPM Cache Fix]${NC} $1"; }
log_error() { echo -e "${RED}[NPM Cache Fix ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[NPM Cache Fix WARN]${NC} $1"; }

# Fix npm cache ownership issues
fix_npm_cache_ownership() {
    log "Checking npm cache ownership..."
    
    # Check if npm cache directory exists and has permission issues
    if [ -d "/.npm" ]; then
        local cache_owner=$(stat -c '%U' /.npm 2>/dev/null || stat -f '%Su' /.npm 2>/dev/null || echo "unknown")
        log "Current npm cache owner: $cache_owner"
        
        if [ "$cache_owner" = "root" ]; then
            log_warn "Npm cache is owned by root, attempting to fix..."
            if command -v sudo >/dev/null 2>&1; then
                if sudo chown -R $(id -u):$(id -g) /.npm 2>/dev/null; then
                    log_success "Successfully fixed npm cache ownership"
                    return 0
                else
                    log_warn "Could not fix npm cache ownership with sudo"
                    return 1
                fi
            else
                log_warn "No sudo available to fix cache ownership"
                return 1
            fi
        else
            log_success "Npm cache ownership is already correct"
            return 0
        fi
    else
        log "No npm cache directory found at /.npm"
        return 0
    fi
}

# Create user-specific npm cache
create_user_cache() {
    local user_cache="/tmp/.npm-cache-$(id -u)"
    log "Creating user-specific npm cache at $user_cache"
    
    mkdir -p "$user_cache"
    export npm_config_cache="$user_cache"
    
    # Also set it globally for npm
    npm config set cache "$user_cache" --global 2>/dev/null || {
        log_warn "Could not set global npm cache config, using environment variable"
    }
    
    log_success "User npm cache created: $user_cache"
    echo "export npm_config_cache=\"$user_cache\"" >> ~/.bashrc 2>/dev/null || true
}

# Clean global npm cache
clean_global_cache() {
    log "Cleaning global npm cache..."
    
    if npm cache clean --force 2>/dev/null; then
        log_success "Global npm cache cleaned successfully"
    else
        log_warn "Could not clean global npm cache (may not exist)"
    fi
    
    # Also clean verify
    if npm cache verify 2>/dev/null; then
        log_success "Npm cache verified successfully"
    else
        log_warn "Npm cache verification failed or not available"
    fi
}

# Fix problematic node_modules
fix_node_modules() {
    local target_dir=${1:-"/app/mcp-servers"}
    
    if [ ! -d "$target_dir" ]; then
        log_warn "Target directory does not exist: $target_dir"
        return 0
    fi
    
    log "Fixing problematic node_modules in $target_dir..."
    
    # Find and fix problematic directories
    find "$target_dir" -name "node_modules" -type d 2>/dev/null | while read -r nm_dir; do
        if [ -d "$nm_dir" ]; then
            log "Processing: $nm_dir"
            
            # Fix permissions first
            find "$nm_dir" -type d -exec chmod 755 {} \; 2>/dev/null || true
            find "$nm_dir" -type f -exec chmod 644 {} \; 2>/dev/null || true
            
            # Remove empty or problematic directories
            find "$nm_dir" -type d -name "type-is" -exec rm -rf {} \; 2>/dev/null || true
            find "$nm_dir" -type d -empty -delete 2>/dev/null || true
        fi
    done
    
    log_success "Node_modules cleanup completed"
}

# Main execution
main() {
    log "Starting npm cache fix process..."
    
    case ${1:-fix} in
        fix|--fix)
            log "Running full npm cache fix..."
            
            # Try to fix ownership first
            if ! fix_npm_cache_ownership; then
                log_warn "Could not fix global cache, creating user cache..."
                create_user_cache
            fi
            
            # Clean cache
            clean_global_cache
            
            # Fix node_modules
            fix_node_modules "$2"
            
            log_success "Npm cache fix process completed!"
            ;;
        ownership|--ownership)
            fix_npm_cache_ownership
            ;;
        clean|--clean)
            clean_global_cache
            ;;
        user-cache|--user-cache)
            create_user_cache
            ;;
        node-modules|--node-modules)
            fix_node_modules "$2"
            ;;
        help|--help|-h)
            echo "NPM Cache Fix Script"
            echo ""
            echo "Usage: $0 [command] [target-dir]"
            echo ""
            echo "Commands:"
            echo "  fix               Fix all npm cache issues (default)"
            echo "  ownership         Fix npm cache ownership only"
            echo "  clean             Clean global npm cache only"
            echo "  user-cache        Create user-specific npm cache"
            echo "  node-modules      Fix problematic node_modules only"
            echo "  help              Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                           # Fix all issues"
            echo "  $0 fix /app/mcp-servers      # Fix all issues in specific directory"
            echo "  $0 ownership                 # Fix ownership only"
            echo "  $0 node-modules /app/        # Fix node_modules in /app/"
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Check if running as script (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
