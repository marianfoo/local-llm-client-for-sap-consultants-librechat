# LibreChat with SAP MCP Servers - Comprehensive Guide

🔧 **Complete setup, troubleshooting, and configuration reference**

This comprehensive guide covers everything you need for production-ready LibreChat with SAP MCP servers. For quick setup, see [MCP_SETUP_GUIDE.md](./MCP_SETUP_GUIDE.md).

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Server Selection & Customization](#server-selection--customization)
3. [Production Installation](#production-installation)
4. [Troubleshooting & Debugging](#troubleshooting--debugging)
5. [Performance & Security](#performance--security)
6. [Development & Advanced Config](#development--advanced-config)

---

## Architecture Overview

### System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Docker Environment                        │
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────────────────────────┐ │
│  │   LibreChat     │    │        Supporting Services           │ │
│  │   (Alpine)      │    │  - MongoDB (chat history)          │ │
│  │ - UI (port 3080)│    │  - Meilisearch (search index)      │ │
│  │ - API server    │    │  - PostgreSQL + pgvector (vectors) │ │
│  │ - SAP Docs MCP  │    │  - RAG API (document processing)   │ │
│  │   (port 3122)   │    └─────────────────────────────────────┘ │
│  └─────────────────┘                                             │
│           │ MCP Protocol                                         │
│           ▼                                                      │
│  ┌─────────────────┐                                             │
│  │ SAP Notes MCP   │ ← Dedicated Playwright sidecar             │
│  │ (Ubuntu/Noble)  │   (only if SAP Notes enabled)              │
│  │ - Port 3123     │                                             │
│  └─────────────────┘                                             │
└─────────────────────────────────────────────────────────────────┘
```

### MCP Server Distribution

| Server | Container | Reason | Required |
|--------|-----------|--------|----------|
| **SAP Docs** | LibreChat (Alpine) | Simple, no browser needed | Always |
| **SAP Notes** | Dedicated sidecar (Ubuntu) | Requires Playwright browsers | Optional |
| **S4/HANA** | LibreChat (Alpine) | Simple HTTP, no browser needed | Optional |
| **ABAP ADT** | LibreChat (Alpine) | Simple HTTP, no browser needed | Optional |

---

## Server Selection & Customization

### Available MCP Servers

| Server | Purpose | Requirements | Setup Complexity |
|--------|---------|--------------|------------------|
| **SAP Docs** ✅ | Documentation & Community search | None | ⭐ Simple |
| **SAP Notes** | Official Knowledge Base | S-User certificate | ⭐⭐⭐ Complex |
| **S4/HANA** | OData services access | SAP system credentials | ⭐⭐ Medium |
| **ABAP ADT** | Direct SAP system access | SAP development system | ⭐⭐ Medium |

### Configuration Scenarios

#### Minimal Setup (SAP Docs Only)
**Best for**: First-time users, learning, documentation-only needs

```yaml
# librechat.yaml
mcpServers:
  sap_docs:
    type: streamable-http
    url: "http://localhost:3122/mcp"
    timeout: 45000
    initTimeout: 15000
  # All others commented out
```

**Environment**: No additional setup needed
**Resources**: Lightweight, fastest startup

#### Developer Setup (Docs + S4/HANA)
**Best for**: Active SAP developers with system access

```yaml
# librechat.yaml  
mcpServers:
  sap_docs:
    type: streamable-http
    url: "http://localhost:3122/mcp"
  s4hana:
    type: streamable-http
    url: "http://localhost:3124/mcp"
    timeout: 45000
    initTimeout: 15000
```

```bash
# .env additions
SAP_DESTINATION_NAME=S4DEV
destinations=[{"name":"S4DEV","url":"https://sap-dev:50001","username":"dev_user","password":"password"}]
```

#### Full Setup (All Servers)
**Best for**: SAP consultants, complete toolchain needs

**Enable all servers in `librechat.yaml` + provide all credentials**

### Configuration Management

**Quick enable/disable commands**:
```bash
# Create helpful alias
alias mcp='docker exec LibreChat /app/scripts/start-mcp-servers.sh'

# Usage examples
mcp status              # Check all servers
mcp health              # Health check all 
mcp restart docs        # Restart specific server
```

**Configuration files relationship**:

| File | Controls What | When to Modify |
|------|---------------|----------------|
| `librechat.yaml` | Which MCP servers LibreChat attempts to connect to | When adding/removing servers |
| `docker-compose.override.yml` | Which containers actually run | When enabling/disabling SAP Notes sidecar |
| `.env` | Credentials for enabled servers | When adding new systems |

**Rule**: Commenting out a server in `librechat.yaml` completely disables it (no network attempts, no resource usage).

---

## Production Installation

### Prerequisites

**Docker Requirements**: [Docker Installation Guide](https://docs.docker.com/get-docker/)
- Docker v20.10+ with Docker Compose v2.0+
- 4GB RAM minimum, 8GB+ recommended
- 5GB+ free disk space

**AI Provider**: [Supported AI Providers](https://www.librechat.ai/docs/configuration/pre_configured_ai)
- OpenAI API key (recommended)
- OR Anthropic, Google, Azure OpenAI
- OR Local models via Ollama

### Production Security Setup

**Official Security Guide**: [LibreChat Security Documentation](https://www.librechat.ai/docs/deployment/security)

**Essential security steps**:
```bash
# 1. Generate unique secrets
JWT_SECRET=$(openssl rand -base64 32)
CREDS_KEY=$(openssl rand -base64 32) 
CREDS_IV=$(openssl rand -hex 32)

# 2. Secure certificate storage
chmod 600 certs/*.pfx
chown root:root certs/*.pfx

# 3. Use environment-specific configs
# Production: prod-certificate.pfx
# Development: dev-certificate.pfx
```

### AI Provider Production Setup

#### OpenAI Production Config
```bash
# .env for production
OPENAI_API_KEY=sk-your-production-key-here
OPENAI_MODELS=gpt-4o,gpt-4,gpt-3.5-turbo

# Optional: Organization settings
OPENAI_ORGANIZATION=org-your-org-id
```

**Cost Management**: [OpenAI Pricing](https://openai.com/pricing)
- Set usage limits in OpenAI dashboard
- Monitor token usage via LibreChat analytics
- Use gpt-3.5-turbo for cost optimization

#### Multi-Provider Setup
```bash
# Support multiple AI providers
OPENAI_API_KEY=sk-your-openai-key
ANTHROPIC_API_KEY=sk-ant-your-anthropic-key
GOOGLE_API_KEY=your-google-key
```

**Configuration**: [LibreChat AI Endpoints](https://www.librechat.ai/docs/configuration/librechat_yaml/ai_endpoints)

---

## Troubleshooting & Debugging

### Common Issues & Solutions

#### MCP Servers Not Visible in LibreChat

**Symptoms**: No MCP tools available in agent creation

**Solutions**:
1. **Enable agents interface** in `librechat.yaml`:
```yaml
interface:
  agents: true  # Required for MCP tools
```

2. **Enable agents endpoint**:
```yaml
endpoints:
  agents:
    disableBuilder: false
    capabilities: ["tools", "file_search", "execute_code"]
```

3. **Verify MCP servers configured** in `librechat.yaml` `mcpServers` section

**Official Documentation**: [LibreChat Agents Configuration](https://www.librechat.ai/docs/configuration/librechat_yaml/object_structure/agents_endpoint)

#### SAP Notes Sidecar Issues

**Symptoms**: `Transport error: fetch failed` for sap_notes

**Debug steps**:
```bash
# 1. Check sidecar container status
docker ps | grep mcp-sap-notes

# 2. Check sidecar logs
docker logs mcp-sap-notes

# 3. Test sidecar health
curl http://localhost:3123/health

# 4. Test from LibreChat container
docker exec LibreChat curl http://sap_notes:3123/health
```

**Common fixes**:
- Verify certificate exists: `ls -la certs/sap.pfx`
- Check certificate password in `.env`
- Restart sidecar: `docker compose restart sap_notes`

#### Build Tool Issues (Alpine Container)

**Symptoms**: `gyp ERR! build error` or `Error: not found: make`

**Automatic Fix**: The entrypoint script handles this:
```bash
apk add --no-cache make gcc g++ python3 python3-dev linux-headers
```

**Manual verification**:
```bash
docker exec LibreChat which make gcc python3
```

### Logging & Monitoring

**LibreChat Debug Mode**: [LibreChat Logging Guide](https://www.librechat.ai/docs/configuration/logging)

```bash
# Enable detailed MCP logging
DEBUG=mcp:*
LOG_LEVEL=debug

# Restart and monitor
docker compose restart
docker logs -f LibreChat | grep MCP
```

**Log locations**:
- LibreChat Core: `docker logs LibreChat`
- MCP Setup: `docker exec LibreChat cat /app/logs/mcp-servers.log`
- SAP Notes Sidecar: `docker logs mcp-sap-notes`

**Health check automation**:
```bash
# Quick health check all services
for service in LibreChat mcp-sap-notes; do
  echo -n "$service: "
  docker inspect $service --format '{{.State.Status}}'
done
```

---

## Performance & Security

### Performance Optimization

**Container resource limits**:
```yaml
# docker-compose.override.yml
api:
  mem_limit: 4g
  memswap_limit: 4g
sap_notes:
  mem_limit: 2g
  shm_size: 1g  # Important for Chrome
```

**Startup optimization**:
- Comment out unused MCP servers in `librechat.yaml`
- Pre-clone repositories for faster startup
- Use persistent volumes for node_modules

**Network optimization**:
```yaml
# Adjust timeouts based on network speed
mcpServers:
  sap_docs:
    timeout: 30000      # Fast networks
    initTimeout: 10000
  sap_notes:
    timeout: 90000
    initTimeout: 30000
```

### Security Hardening

**Official Security Guide**: [LibreChat Security Best Practices](https://www.librechat.ai/docs/deployment/security)

**Production security checklist**:
```bash
# 1. Unique secrets (never use defaults)
JWT_SECRET=$(openssl rand -base64 32)
CREDS_KEY=$(openssl rand -base64 32)
CREDS_IV=$(openssl rand -hex 32)

# 2. Secure database connection
MONGO_URI=mongodb://secure-user:strong-password@mongo:27017/LibreChat

# 3. MCP server access tokens
ACCESS_TOKEN=$(openssl rand -base64 32)
```

**Certificate security**:
```bash
# Restrict certificate permissions
chmod 600 certs/*.pfx
# Use separate certificates per environment
```

**Network security**:
```yaml
# Custom network for isolation
networks:
  librechat_secure:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
```

---

## Development & Advanced Config

### Custom MCP Server Integration

**Official MCP Documentation**: [LibreChat MCP Server Configuration](https://www.librechat.ai/docs/configuration/librechat_yaml/object_structure/mcp_servers)

**Adding custom servers**:

**stdio-based server**:
```yaml
mcpServers:
  my_custom_server:
    type: stdio
    command: node
    args: ["/path/to/server.js"]
    serverInstructions: |
      Custom server for specific business logic
```

**HTTP-based server**:
```yaml
mcpServers:
  my_http_server:
    type: streamable-http
    url: "http://localhost:3000/mcp"
    headers:
      Authorization: "Bearer ${MY_API_KEY}"
    timeout: 30000
    initTimeout: 10000
```

### Development Workflow

**Modifying existing MCP servers**:
```bash
# 1. Make changes locally in mcp-servers/
# 2. Rebuild in container
docker exec LibreChat sh -c "cd /app/mcp-servers/mcp-sap-docs && npm run build"
# 3. Restart server (auto-restarts via entrypoint)
docker exec LibreChat pkill -f "mcp-sap-docs"
```

**Development debugging**:
```bash
# Enable full debug mode
NODE_ENV=development
DEBUG=*
LOG_LEVEL=debug

# Use MCP inspector for stdio servers
npx @modelcontextprotocol/inspector node server.js
```

### LibreChat Agent Creation

**Official Documentation**: [LibreChat Agents Guide](https://www.librechat.ai/docs/features/agents)

**SAP-specific agent examples**:

**SAP Developer Agent**:
```yaml
name: "SAP Developer Assistant"
instructions: |
  You are a SAP development expert. Use MCP tools to:
  - Search SAP documentation for best practices
  - Find SAP Notes for error resolution
  - Access ABAP source code and structures
  - Discover S/4HANA OData services
  Always cite specific SAP documentation and Note numbers.
capabilities: ["tools"]
```

**Agent Best Practices**: [LibreChat Agent Configuration](https://www.librechat.ai/docs/configuration/librechat_yaml/object_structure/agents_endpoint)

### Backup & Migration

**Configuration backup**:
```bash
# Essential files to backup
cp .env .env.backup
cp librechat.yaml librechat.yaml.backup
cp docker-compose.override.yml docker-compose.override.yml.backup
tar -czf certs-backup.tar.gz certs/
```

**Data migration**:
```bash
# MongoDB backup
docker exec chat-mongodb mongodump --out /backup
docker cp chat-mongodb:/backup ./mongodb-backup

# Meilisearch backup
docker exec chat-meilisearch cp -r /data.ms ./meilisearch-backup
```

**Upgrade process**:
```bash
# 1. Backup current setup
docker compose down
cp -r . ../LibreChat-backup

# 2. Pull latest changes  
git pull origin main

# 3. Rebuild containers
docker compose build --no-cache

# 4. Start with new version
docker compose up -d
```

---

## Official Documentation References

### LibreChat Core Documentation
- **Main Documentation**: https://www.librechat.ai/docs
- **Docker Installation**: https://www.librechat.ai/docs/configuration/docker_compose_install
- **Environment Variables**: https://www.librechat.ai/docs/configuration/environment_variables
- **MCP Server Configuration**: https://www.librechat.ai/docs/configuration/librechat_yaml/object_structure/mcp_servers
- **Agents Setup**: https://www.librechat.ai/docs/features/agents
- **AI Endpoints**: https://www.librechat.ai/docs/configuration/librechat_yaml/ai_endpoints
- **Security Best Practices**: https://www.librechat.ai/docs/deployment/security

### SAP Resources  
- **SAP Help Portal**: https://help.sap.com
- **SAP Community**: https://community.sap.com
- **SAP Support Portal**: https://support.sap.com (S-User required)
- **SAP Developer Center**: https://developers.sap.com

### MCP Protocol Documentation
- **Model Context Protocol**: https://modelcontextprotocol.io
- **MCP Specification**: https://spec.modelcontextprotocol.io
- **LibreChat MCP Support**: https://modelcontextprotocol.io/clients#librechat

---

## Getting Help & Support

### LibreChat Community
- **Discord**: https://discord.librechat.ai
- **GitHub Issues**: https://github.com/danny-avila/LibreChat/issues
- **Documentation**: https://www.librechat.ai/docs

### SAP MCP Server Repositories
- **SAP Docs**: https://github.com/marianfoo/mcp-sap-docs  
- **SAP Notes**: https://github.com/marianfoo/mcp-sap-notes
- **S4/HANA OData**: https://github.com/marianfoo/btp-sap-odata-to-mcp-server
- **ABAP ADT**: https://github.com/marianfoo/mcp-abap-adt

### Issue Reporting

**When reporting issues, include**:
1. **Environment**: Docker version, OS, LibreChat version
2. **Logs**: Relevant log snippets (sanitize credentials!)
3. **Configuration**: Your `librechat.yaml` (remove secrets)
4. **Steps**: Clear reproduction steps

---

## Conclusion

This comprehensive guide provides everything needed for production LibreChat with SAP MCP integration. The modular architecture allows users to enable exactly the SAP tools they need:

- ✅ **SAP Documentation Search** (always available)
- ✅ **SAP Knowledge Base Access** (with certificate)
- ✅ **Live S/4HANA Integration** (with credentials)  
- ✅ **Direct ABAP Development** (with system access)

The **sidecar architecture** ensures reliable browser-based authentication while keeping the core LibreChat system lightweight and maintainable.

**Next Steps**:
1. Follow the [Quick Setup Guide](./MCP_SETUP_GUIDE.md) for installation
2. Create specialized agents using LibreChat's agent builder
3. Customize server instructions for your specific use cases
4. Implement monitoring and backup strategies for production use

**Happy AI-powered SAP development!** 🚀
