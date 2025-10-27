#!/bin/bash
# MCP Server Management Script
# Helper functions to start, stop, restart, and check health of individual MCP servers

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Detect if running in Docker container or on host
if [ -d "/app/mcp-servers" ]; then
    MCP_DIR="/app/mcp-servers"
    LOG_FILE="/app/logs/mcp-servers.log"
else
    # Host system paths
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
    MCP_DIR="$PROJECT_ROOT/mcp-servers"
    LOG_FILE="$PROJECT_ROOT/logs/mcp-servers.log"
fi

# Logging functions
log() { echo -e "${BLUE}[MCP Manager]${NC} $1"; }
log_success() { echo -e "${GREEN}[MCP Manager]${NC} $1"; }
log_error() { echo -e "${RED}[MCP Manager ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[MCP Manager WARN]${NC} $1"; }

# NPM Cache Management Functions
fix_npm_cache() {
    log "Fixing npm cache ownership issues..."
    
    # Check if npm cache directory exists and has permission issues
    if [ -d "/.npm" ]; then
        local cache_owner=$(stat -c '%U' /.npm 2>/dev/null || stat -f '%Su' /.npm 2>/dev/null || echo "unknown")
        if [ "$cache_owner" = "root" ]; then
            log_warn "Npm cache is owned by root, attempting to fix..."
            if command -v sudo >/dev/null 2>&1; then
                sudo chown -R $(id -u):$(id -g) /.npm 2>/dev/null || {
                    log_warn "Could not fix npm cache ownership, using alternative cache location"
                    export npm_config_cache="/tmp/.npm-cache-$(id -u)"
                    mkdir -p "$npm_config_cache"
                }
            else
                log_warn "No sudo available, using alternative cache location"
                export npm_config_cache="/tmp/.npm-cache-$(id -u)"
                mkdir -p "$npm_config_cache"
            fi
        fi
    else
        # Create npm cache in user-writable location if it doesn't exist
        export npm_config_cache="/tmp/.npm-cache-$(id -u)"
        mkdir -p "$npm_config_cache"
        log "Created npm cache at $npm_config_cache"
    fi
}

clean_node_modules() {
    local server_dir=$1
    local server_name=$2
    
    log "Cleaning node_modules for $server_name..."
    cd "$server_dir"
    
    # Remove problematic node_modules with force
    if [ -d "node_modules" ]; then
        log "Removing existing node_modules..."
        rm -rf node_modules 2>/dev/null || {
            log_warn "Standard removal failed, using force cleanup..."
            find node_modules -type d -exec chmod 755 {} \; 2>/dev/null || true
            rm -rf node_modules 2>/dev/null || true
        }
    fi
    
    # Clear npm cache for this directory
    npm cache clean --force 2>/dev/null || true
}

safe_npm_install() {
    local server_dir=$1
    local server_name=$2
    
    log "Performing safe npm install for $server_name..."
    cd "$server_dir"
    
    # Fix cache issues first
    fix_npm_cache
    
    # Clean existing modules if they exist
    clean_node_modules "$server_dir" "$server_name"
    
    # Install with safe options (removed --prefer-offline to ensure complete dependency resolution)
    local npm_opts="--no-audit --no-fund"
    if [ -n "$npm_config_cache" ]; then
        npm_opts="$npm_opts --cache $npm_config_cache"
    fi
    
    log "Running: npm install $npm_opts"
    # Use npm install instead of npm ci for more reliable dependency resolution
    if npm install $npm_opts >> "$LOG_FILE" 2>&1; then
        log_success "npm install completed successfully for $server_name"
        return 0
    else
        log_error "npm install failed, trying npm ci as fallback..."
        if npm ci $npm_opts >> "$LOG_FILE" 2>&1; then
            log_success "npm ci (fallback) completed for $server_name"
            return 0
        else
            log_error "Both npm install and npm ci failed for $server_name"
            return 1
        fi
    fi
}

# Health check function for HTTP servers
health_check() {
    local server_name=$1
    local port=$2
    local endpoint=${3:-/mcp}
    
    log "Checking health of $server_name on port $port..."
    
    # Try health endpoint first, then MCP endpoint
    if curl -f -s -o /dev/null "http://localhost:$port/health" 2>/dev/null; then
        log_success "$server_name is healthy ✓ (health endpoint)"
        return 0
    elif curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port$endpoint" | grep -q "400"; then
        # MCP servers return 400 for invalid requests, which means they're running
        log_success "$server_name is healthy ✓ (MCP endpoint responding)"
        return 0
    elif nc -z localhost "$port" 2>/dev/null; then
        log_success "$server_name is healthy ✓ (port responding)"
        return 0
    else
        log_error "$server_name is not responding ✗"
        return 1
    fi
}

# Start SAP Docs Server
start_sap_docs() {
    log "Starting SAP Docs MCP Server..."
    
    # Fix npm cache issues before starting
    fix_npm_cache
    
    cd "$MCP_DIR/mcp-sap-docs"
    MCP_PORT=${MCP_PORT:-3122} npm run start:streamable >> "$LOG_FILE" 2>&1 &
    local pid=$!
    log_success "SAP Docs server started (PID: $pid)"
    sleep 3
    health_check "SAP Docs" "${MCP_PORT:-3122}"
}

# Start SAP Notes Server
start_sap_notes() {
    if [ -z "$PFX_PATH" ] || [ ! -f "$PFX_PATH" ]; then
        log_error "Cannot start SAP Notes server: PFX_PATH not set or certificate not found"
        return 1
    fi
    
    log "Starting SAP Notes MCP Server..."
    
    # Fix npm cache issues before starting
    fix_npm_cache
    
    cd "$MCP_DIR/mcp-sap-notes"
    HTTP_PORT=${HTTP_PORT:-3123} npm run serve:http >> "$LOG_FILE" 2>&1 &
    local pid=$!
    log_success "SAP Notes server started (PID: $pid)"
    sleep 3
    health_check "SAP Notes" "${HTTP_PORT:-3123}"
}

# Start S4/HANA OData Server
start_s4_hana() {
    if [ -z "$SAP_DESTINATION_NAME" ] || [ -z "$destinations" ]; then
        log_error "Cannot start S4/HANA server: SAP_DESTINATION_NAME or destinations not set"
        return 1
    fi
    
    log "Starting S4/HANA OData MCP Server..."
    
    # Fix npm cache issues before starting
    fix_npm_cache
    
    cd "$MCP_DIR/btp-sap-odata-to-mcp-server"
    npm run start:http >> "$LOG_FILE" 2>&1 &
    local pid=$!
    log_success "S4/HANA server started (PID: $pid)"
    sleep 3
    health_check "S4/HANA" "3124"
}

# Start ABAP ADT Server
start_abap_adt() {
    if [ -z "$SAP_URL" ] || [ -z "$SAP_USERNAME" ]; then
        log_error "Cannot start ABAP ADT server: SAP_URL or SAP_USERNAME not set"
        return 1
    fi
    
    log "Starting ABAP ADT MCP Server..."
    
    # Fix npm cache issues before starting
    fix_npm_cache
    
    cd "$MCP_DIR/mcp-abap-adt"
    
    if grep -q '"start:http"' package.json; then
        npm run start:http >> "$LOG_FILE" 2>&1 &
    else
        node dist/index.js >> "$LOG_FILE" 2>&1 &
    fi
    
    local pid=$!
    log_success "ABAP ADT server started (PID: $pid)"
    sleep 3
    health_check "ABAP ADT" "3234"
}

# Stop a server by name pattern
stop_server() {
    local server_pattern=$1
    local server_name=$2
    
    log "Stopping $server_name..."
    local pids=$(ps aux | grep "$server_pattern" | grep -v grep | awk '{print $2}')
    
    if [ -z "$pids" ]; then
        log_warn "$server_name is not running"
        return 0
    fi
    
    echo "$pids" | xargs kill -15 2>/dev/null || true
    sleep 2
    
    # Force kill if still running
    local remaining=$(ps aux | grep "$server_pattern" | grep -v grep | awk '{print $2}')
    if [ -n "$remaining" ]; then
        echo "$remaining" | xargs kill -9 2>/dev/null || true
    fi
    
    log_success "$server_name stopped"
}

# Stop all MCP servers
stop_all() {
    log "Stopping all MCP servers..."
    stop_server "mcp-sap-docs" "SAP Docs"
    stop_server "mcp-sap-notes" "SAP Notes"
    stop_server "btp-sap-odata-to-mcp-server" "S4/HANA"
    stop_server "mcp-abap-adt" "ABAP ADT"
    log_success "All MCP servers stopped"
}

# Start all MCP servers
start_all() {
    log "Starting all MCP servers..."
    start_sap_docs || log_warn "SAP Docs failed to start"
    start_sap_notes || log_warn "SAP Notes failed to start"
    start_s4_hana || log_warn "S4/HANA failed to start"
    start_abap_adt || log_warn "ABAP ADT failed to start"
    log_success "All MCP servers start commands issued"
}

# Restart a specific server
restart_server() {
    local server=$1
    case $server in
        docs|sap-docs)
            stop_server "mcp-sap-docs" "SAP Docs"
            start_sap_docs
            ;;
        notes|sap-notes)
            stop_server "mcp-sap-notes" "SAP Notes"
            start_sap_notes
            ;;
        s4|s4hana|odata)
            stop_server "btp-sap-odata-to-mcp-server" "S4/HANA"
            start_s4_hana
            ;;
        adt|abap|abap-adt)
            stop_server "mcp-abap-adt" "ABAP ADT"
            start_abap_adt
            ;;
        all)
            stop_all
            sleep 2
            start_all
            ;;
        *)
            log_error "Unknown server: $server"
            log "Valid options: docs, notes, s4, adt, all"
            return 1
            ;;
    esac
}

# Check health of all servers
health_check_all() {
    log "Checking health of all MCP servers..."
    echo ""
    health_check "SAP Docs" "${MCP_PORT:-3122}" "/mcp" || true
    health_check "SAP Notes" "${HTTP_PORT:-3123}" "/mcp" || true
    health_check "S4/HANA" "3124" "/mcp" || true
    health_check "ABAP ADT" "3234" "/mcp" || true
    echo ""
}

# Show status of all servers
status() {
    log "MCP Servers Status:"
    echo ""
    
    # POSIX-compatible server list (no arrays)
    local servers="mcp-sap-docs:SAP Docs|mcp-sap-notes:SAP Notes|btp-sap-odata-to-mcp-server:S4/HANA|mcp-abap-adt:ABAP ADT"
    
    # Process each server (POSIX-compatible)
    echo "$servers" | tr '|' '\n' | while IFS=':' read -r pattern name; do
        local pids=$(ps aux | grep "$pattern" | grep -v grep | awk '{print $2}')
        
        if [ -n "$pids" ]; then
            log_success "$name: RUNNING (PIDs: $pids)"
        else
            log_warn "$name: STOPPED"
        fi
    done
    echo ""
}

# Rebuild a specific server
rebuild() {
    local server=$1
    local repo_name=""
    
    case $server in
        docs|sap-docs) repo_name="mcp-sap-docs" ;;
        notes|sap-notes) repo_name="mcp-sap-notes" ;;
        s4|s4hana|odata) repo_name="btp-sap-odata-to-mcp-server" ;;
        adt|abap|abap-adt) repo_name="mcp-abap-adt" ;;
        *)
            log_error "Unknown server: $server"
            return 1
            ;;
    esac
    
    log "Rebuilding $repo_name..."
    local server_dir="$MCP_DIR/$repo_name"
    
    # Use safe npm install to avoid cache issues
    if ! safe_npm_install "$server_dir" "$repo_name"; then
        log_error "Failed to install dependencies for $repo_name"
        return 1
    fi
    
    cd "$server_dir"
    if grep -q '"build"' package.json; then
        log "Building..."
        if npm run build >> "$LOG_FILE" 2>&1; then
            log_success "$repo_name rebuilt successfully"
        else
            log_error "Build failed for $repo_name"
            return 1
        fi
    else
        log_warn "No build script found, dependencies installed"
    fi
}

# Clean npm caches for all servers
clean_caches() {
    log "Cleaning npm caches for all MCP servers..."
    
    # Fix global npm cache issues first
    fix_npm_cache
    
    # Clean individual server caches
    # POSIX-compatible server list
    local servers="mcp-sap-docs mcp-sap-notes btp-sap-odata-to-mcp-server mcp-abap-adt"
    
    for server in $servers; do
        local server_dir="$MCP_DIR/$server"
        if [ -d "$server_dir" ]; then
            log "Cleaning cache for $server..."
            clean_node_modules "$server_dir" "$server"
        else
            log_warn "Server directory not found: $server_dir"
        fi
    done
    
    # Clean global npm cache
    log "Cleaning global npm cache..."
    npm cache clean --force 2>/dev/null || true
    
    # Clean temporary npm cache if we created one
    if [ -n "$npm_config_cache" ] && [ -d "$npm_config_cache" ]; then
        log "Cleaning temporary npm cache: $npm_config_cache"
        rm -rf "$npm_config_cache" 2>/dev/null || true
    fi
    
    log_success "Cache cleanup completed"
}

# Show usage
usage() {
    echo "MCP Server Management Script"
    echo ""
    echo "Usage: $0 <command> [server]"
    echo ""
    echo "Commands:"
    echo "  start [server]     Start a specific server or all servers"
    echo "  stop [server]      Stop a specific server or all servers"
    echo "  restart [server]   Restart a specific server or all servers"
    echo "  status             Show status of all servers"
    echo "  health             Check health of all servers"
    echo "  rebuild <server>   Rebuild a specific server"
    echo "  clean-cache        Clean npm caches for all servers"
    echo "  logs               Show recent MCP server logs"
    echo ""
    echo "Servers: docs, notes, s4, adt, all (default)"
    echo ""
    echo "Examples:"
    echo "  $0 start all          # Start all MCP servers"
    echo "  $0 restart docs       # Restart SAP Docs server"
    echo "  $0 health             # Check health of all servers"
    echo "  $0 rebuild adt        # Rebuild ABAP ADT server"
    echo "  $0 clean-cache        # Clean npm caches for all servers"
}

# Show recent logs
show_logs() {
    if [ -f "$LOG_FILE" ]; then
        log "Recent MCP server logs (last 50 lines):"
        echo ""
        tail -n 50 "$LOG_FILE"
    else
        log_warn "Log file not found: $LOG_FILE"
    fi
}

# Main command handler
case ${1:-help} in
    start)
        if [ -z "$2" ] || [ "$2" = "all" ]; then
            start_all
        else
            restart_server "$2"
        fi
        ;;
    stop)
        if [ -z "$2" ] || [ "$2" = "all" ]; then
            stop_all
        else
            stop_server "$2" "$2"
        fi
        ;;
    restart)
        restart_server "${2:-all}"
        ;;
    status)
        status
        ;;
    health)
        health_check_all
        ;;
    rebuild)
        if [ -z "$2" ]; then
            log_error "Please specify a server to rebuild"
            usage
            exit 1
        fi
        rebuild "$2"
        ;;
    clean-cache)
        clean_caches
        ;;
    logs)
        show_logs
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        log_error "Unknown command: $1"
        usage
        exit 1
        ;;
esac

