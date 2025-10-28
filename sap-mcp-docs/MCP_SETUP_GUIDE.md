# LibreChat with SAP MCP Servers - Setup Guide

🚀 **Get LibreChat with SAP MCP integration running in 10 minutes!**

## ⚡ Quick Setup (5 steps)

### Step 1: Clone Repository
```bash
git clone https://github.com/danny-avila/LibreChat.git
cd LibreChat
```

### Step 2: Setup Configuration Files
```bash
cp .env.example .env
cp librechat.example.yaml librechat.yaml
```

### Step 3: Configure AI Provider (Required)

**Option A: OpenAI (Easiest)**
```bash
# Add to .env file:
OPENAI_API_KEY=sk-your-api-key-here
```

**Option B: Ollama (Free, Local)**
```bash
# Install Ollama first: https://ollama.ai
ollama pull llama3.1:8b
# No .env changes needed
```

### Step 4: Choose Your SAP MCP Servers

**Add the servers you want to your `librechat.yaml`:**

```yaml
mcpServers:
  # SAP Documentation Server - Public SAP Help and Community content
  sap_docs:
    type: streamable-http
    url: "http://localhost:3122/mcp"
    timeout: 45000
    initTimeout: 15000
    serverInstructions: |
      You provide access to official SAP Help/Docs and SAP Community content.
      Use for configuration/how-to, conceptual guidance, and product docs (UI5, CAP, ABAP).
      Prefer a search→get pattern:
        • sap_help_search(query) → sap_help_get(result_id) to retrieve full content.
      Build concise queries with SAP terms (e.g., "S/4HANA MRP Live", "sap.m.Button properties").
      If results are sparse or off-topic, refine product+topic terms before switching servers.

  # SAP Notes Server - Official SAP Knowledge Base (requires S-User certificate)
  # Running in dedicated Playwright sidecar container
  sap_notes:
    type: streamable-http
    url: "http://sap_notes:3123/mcp"
    timeout: 90000
    initTimeout: 30000
    serverInstructions: |
      You search official SAP Notes (knowledge base).
      Use when the user mentions "note", "OSS number", "error", "issue", "fix", or a 6-8 digit Note ID.
      Pattern:
        • If a Note ID is present → sap_note_get(id).
        • Otherwise → sap_note_search(q) then pick relevant IDs and call sap_note_get.
      If zero results, try a narrower phrasing or switch to sap_docs for conceptual guidance.

  # # S/4HANA OData Server - BTP-connected S/4HANA system access
  # s4hana:
  #   type: streamable-http
  #   url: "http://localhost:3000/mcp"
  #   timeout: 45000
  #   initTimeout: 15000
  #   serverInstructions: |
  #     S/4HANA OData services: service discovery, metadata, and business object access (e.g., Business Partner, Sales Order).
  #     Use for service names, entity sets, fields, and CRUD examples.
  #     If the request is about "how to configure" or conceptual tasks, prefer sap_docs first.
  #     Favor safe, read-only examples unless the user explicitly requests write operations.

  # # # ABAP ADT Server - Direct SAP system access via ADT
  # abap_adt:
  #   type: streamable-http
  #   url: "http://localhost:3234/mcp"
  #   timeout: 45000
  #   initTimeout: 15000
  #   serverInstructions: |
  #     ABAP Development Tools (ADT) server for SAP system access.
  #     Provides tools to retrieve ABAP source code, table structures, and development objects.
  #     Available tools: GetProgram, GetClass, GetFunctionGroup, GetFunction, GetStructure, 
  #     GetTable, GetTableContents, GetPackage, GetTypeInfo, GetInclude, SearchObject, 
  #     GetInterface, GetTransaction.
  #     Use for ABAP development tasks, code analysis, and system exploration.
```

### Step 5: Add Credentials (Only for Servers You Enabled)

**For SAP Notes:**
```bash
mkdir -p certs
cp /path/to/your-certificate.pfx certs/sap.pfx

# Add to .env:
PFX_PATH=/app/certs/sap.pfx
PFX_PASSPHRASE=your-certificate-password
```

**For S4/HANA:**
```bash
# Add to .env:
SAP_DESTINATION_NAME=S4
destinations=[{"name":"S4","url":"https://your-system:50001","username":"user","password":"pass"}]
```

**For ABAP ADT:**
```bash
# Add to .env:
SAP_URL=https://your-sap-system.com:8000
SAP_USERNAME=your_username
SAP_PASSWORD=your_password  
SAP_CLIENT=100
```

## 🚀 Start LibreChat

```bash
docker compose up -d
```

**⏱️ Startup Time:**
- **First run**: 8-15 minutes (downloads images, clones repos, installs dependencies)
- **Subsequent runs**: 1-2 minutes

**Why it takes time:**
- Downloads Microsoft Playwright image (764MB) for SAP Notes
- Clones 4 MCP server repositories from GitHub
- Installs npm dependencies and compiles TypeScript

## ✅ Access LibreChat

Open: **http://localhost:3080**

Create an account and start using LibreChat with SAP MCP integration! 🎉

## 🛠️ **Management Commands**

**Check server status:**
```bash
docker exec LibreChat /app/scripts/start-mcp-servers.sh status
docker exec LibreChat /app/scripts/start-mcp-servers.sh health
```

**Restart servers:**
```bash
# Restart specific server
docker exec LibreChat /app/scripts/start-mcp-servers.sh restart docs

# Restart all
docker compose restart
```

**View logs:**
```bash
# MCP server logs
docker exec LibreChat cat /app/logs/mcp-servers.log

# LibreChat logs
docker logs LibreChat | grep MCP
```

## 🧪 **Test Your Setup**

**Try these queries in LibreChat:**

- **SAP Docs**: `"Show me how to create a UI5 button"`
- **SAP Notes**: `"Find SAP Notes about OData error 415"`  
- **S4/HANA**: `"List available OData services"`
- **ABAP ADT**: `"Get source code for program SAPMSYST"`

## 🐛 **Quick Troubleshooting**

**Servers not starting?**
```bash
# Check what's running
docker ps | grep -E "(LibreChat|mcp-sap)"

# Check logs for errors
docker logs LibreChat | grep -E "(MCP|Error)"
```

**LibreChat can't see MCP tools?**
1. Verify `agents: true` in `librechat.yaml` interface section
2. Check MCP servers are uncommented in `librechat.yaml`
3. Restart: `docker compose restart`

**Port conflicts?**
```bash
# Find what's using port 3080
lsof -i :3080
# Change port in .env: PORT=3081
```

## 🔧 **Customization Options**

**Choose which MCP servers you want:**

| Server | Purpose | Requires |
|--------|---------|----------|
| **SAP Docs** ✅ | Documentation & Community search | Nothing (always works) |
| **SAP Notes** | Official Knowledge Base search | S-User certificate |
| **S4/HANA** | OData services access | SAP system credentials |
| **ABAP ADT** | Direct SAP system access | SAP development system |

**To disable a server**: Comment it out in `librechat.yaml`  
**To disable SAP Notes sidecar**: Comment out `sap_notes` service in `docker-compose.override.yml`

**💡 Recommendation**: Start with **SAP Docs only** (no setup needed), then add others as needed.

## 🆘 **Need Help?**

- **LibreChat Docs**: https://www.librechat.ai/docs
- **LibreChat Discord**: https://discord.librechat.ai
- **Issue Reports**: Include logs and sanitized config files
