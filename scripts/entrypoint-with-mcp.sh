#!/bin/sh
# LibreChat Entrypoint with MCP Servers
# This script clones, builds, and starts all SAP MCP servers before launching LibreChat

# Don't exit on error for npm commands (they may have permission warnings but still work)
# set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

MCP_DIR="/app/mcp-servers"
LOG_FILE="/app/logs/mcp-servers.log"

# Ensure logs directory exists
mkdir -p /app/logs

# Function to log messages
log() {
    echo -e "${BLUE}[MCP Setup]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[MCP Setup]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[MCP Setup ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[MCP Setup WARN]${NC} $1" | tee -a "$LOG_FILE"
}

# Start timestamp
log "================================================"
log "Starting MCP Servers Setup - $(date)"
log "================================================"

# Install build dependencies needed for native modules
log "Installing build dependencies..."
if command -v apk >/dev/null 2>&1; then
    # Alpine Linux (LibreChat container)
    apk add --no-cache make gcc g++ python3 python3-dev linux-headers git 2>&1 | tee -a "$LOG_FILE" || log_warn "Build dependencies installation had warnings"
elif command -v apt-get >/dev/null 2>&1; then
    # Debian/Ubuntu
    apt-get update && apt-get install -y build-essential python3-dev git 2>&1 | tee -a "$LOG_FILE" || log_warn "Build dependencies installation had warnings"
else
    log_warn "Unknown package manager, skipping build dependencies installation"
fi

# Create MCP servers directory if it doesn't exist
mkdir -p "$MCP_DIR"

# Change to MCP directory
cd "$MCP_DIR"

# Function to install dependencies
install_deps() {
    local repo_name=$1
    if [ ! -d "$MCP_DIR/$repo_name" ]; then
        log_error "Repository $repo_name not found in $MCP_DIR"
        return 1
    fi
    
    log "Installing dependencies for $repo_name..."
    cd "$MCP_DIR/$repo_name"
    
    # Use npm install for better compatibility with Alpine and missing build tools
    npm install --no-audit --no-fund 2>&1 | tee -a "$LOG_FILE" || log_warn "npm install completed with warnings for $repo_name"
    cd "$MCP_DIR"
}

# Function to build a server
build_server() {
    local repo_name=$1
    if [ ! -d "$MCP_DIR/$repo_name" ]; then
        log_error "Repository $repo_name not found in $MCP_DIR"
        return 1
    fi
    
    log "Building $repo_name..."
    cd "$MCP_DIR/$repo_name"
    
    # SAP Notes server now runs in dedicated Playwright sidecar container
    # No special handling needed here
    
    if grep -q '"build"' package.json 2>/dev/null; then
        npm run build 2>&1 | tee -a "$LOG_FILE" && log_success "$repo_name built successfully" || log_warn "$repo_name build had warnings (but may still work)"
    else
        log_warn "No build script found for $repo_name, skipping..."
    fi
    cd "$MCP_DIR"
}

# Function to clone a repository if it doesn't exist
clone_repo_if_missing() {
    local repo_name=$1
    local repo_url=$2
    
    if [ ! -d "$MCP_DIR/$repo_name" ]; then
        log "Repository $repo_name not found. Cloning from $repo_url..."
        git clone --depth 1 "$repo_url" "$MCP_DIR/$repo_name" 2>&1 | tee -a "$LOG_FILE"
        if [ $? -eq 0 ]; then
            log_success "Successfully cloned $repo_name"
        else
            log_error "Failed to clone $repo_name from $repo_url"
            return 1
        fi
    else
        log "Repository $repo_name already exists, skipping clone"
    fi
}

# Check if MCP server repositories exist, clone them if missing
log "Checking and setting up MCP server repositories..."

# Repository URLs
SAP_DOCS_URL="https://github.com/marianfoo/mcp-sap-docs"
SAP_NOTES_URL="https://github.com/marianfoo/mcp-sap-notes"
BTP_ODATA_URL="https://github.com/marianfoo/btp-sap-odata-to-mcp-server"
ABAP_ADT_URL="https://github.com/marianfoo/mcp-abap-adt"

# Clone missing repositories
clone_repo_if_missing "mcp-sap-docs" "$SAP_DOCS_URL"
clone_repo_if_missing "mcp-sap-notes" "$SAP_NOTES_URL"
clone_repo_if_missing "btp-sap-odata-to-mcp-server" "$BTP_ODATA_URL"
clone_repo_if_missing "mcp-abap-adt" "$ABAP_ADT_URL"

# Final check - if any repository is still missing, exit with error
if [ ! -d "$MCP_DIR/mcp-sap-docs" ] || [ ! -d "$MCP_DIR/mcp-sap-notes" ] || [ ! -d "$MCP_DIR/btp-sap-odata-to-mcp-server" ] || [ ! -d "$MCP_DIR/mcp-abap-adt" ]; then
    log_error "One or more MCP server repositories could not be set up. Please check network connectivity and repository access."
    log_error "Expected directories: mcp-sap-docs, mcp-sap-notes, btp-sap-odata-to-mcp-server, mcp-abap-adt"
    exit 1
fi

log_success "All MCP server repositories are ready"

# Install dependencies for all servers
log "Installing dependencies for all MCP servers..."
install_deps "mcp-sap-docs"
install_deps "mcp-sap-notes"
install_deps "btp-sap-odata-to-mcp-server"
install_deps "mcp-abap-adt"

# Build all servers
log "Building all MCP servers..."
build_server "mcp-sap-docs"
build_server "mcp-sap-notes"
build_server "btp-sap-odata-to-mcp-server"
build_server "mcp-abap-adt"

# Start MCP servers in background
log "Starting MCP servers..."

# 1. SAP Docs Server (port 3122)
log "Starting SAP Docs MCP Server on port ${MCP_PORT:-3122}..."
cd "$MCP_DIR/mcp-sap-docs"
MCP_PORT=${MCP_PORT:-3122} npm run start:streamable >> "$LOG_FILE" 2>&1 &
SAP_DOCS_PID=$!
log_success "SAP Docs server started (PID: $SAP_DOCS_PID)"

# 2. SAP Notes Server - now runs in dedicated sidecar container
log "SAP Notes server runs in dedicated Playwright sidecar container (sap_notes service)"

# 3. S4/HANA OData Server (port 3124) - only if credentials are provided
if [ -n "$SAP_DESTINATION_NAME" ] && [ -n "$destinations" ]; then
    log "Starting S4/HANA OData MCP Server on port 3124..."
    cd "$MCP_DIR/btp-sap-odata-to-mcp-server"
    npm run start:http >> "$LOG_FILE" 2>&1 &
    S4_HANA_PID=$!
    log_success "S4/HANA server started (PID: $S4_HANA_PID)"
else
    log_warn "S4/HANA server not started: SAP_DESTINATION_NAME or destinations not set"
fi

# 4. ABAP ADT Server (port 3234) - only if credentials are provided
if [ -n "$SAP_URL" ] && [ -n "$SAP_USERNAME" ]; then
    log "Starting ABAP ADT MCP Server on port 3234..."
    cd "$MCP_DIR/mcp-abap-adt"
    # Check if there's a start:http script, otherwise use node directly
    if grep -q '"start:http"' package.json; then
        MCP_PORT=3234 npm run start:http >> "$LOG_FILE" 2>&1 &
    else
        # Fallback: run with MCP inspector in HTTP mode
        MCP_PORT=3234 node dist/index.js >> "$LOG_FILE" 2>&1 &
    fi
    ABAP_ADT_PID=$!
    log_success "ABAP ADT server started (PID: $ABAP_ADT_PID)"
else
    log_warn "ABAP ADT server not started: SAP_URL or SAP_USERNAME not set"
fi

# Wait for servers to initialize
log "Waiting 10 seconds for MCP servers to initialize..."
sleep 10

# Verify servers are running
log "Verifying MCP servers..."
ps aux | grep -E "(mcp-sap|btp-sap|mcp-abap)" | grep -v grep | tee -a "$LOG_FILE" || log_warn "Some MCP servers may not be running"

log_success "================================================"
log_success "MCP Servers setup complete!"
log_success "Logs available at: $LOG_FILE"
log_success "================================================"

# Now start the original LibreChat application
log "Starting LibreChat application..."
cd /app

# Execute the original LibreChat entrypoint
# This should match the original CMD from the LibreChat Docker image
exec npm run backend

