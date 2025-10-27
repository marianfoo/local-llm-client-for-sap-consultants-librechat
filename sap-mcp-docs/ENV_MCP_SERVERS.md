# MCP Server Environment Variables

This file documents all environment variables needed for SAP MCP servers. Add these to your `.env` file.

## Quick Setup

**Prerequisites**: You should already have LibreChat's core `.env` configured. If not, see the [official documentation](https://www.librechat.ai/docs/configuration/dotenv).

Add only the sections you need to your existing `.env` file:

```bash
# ==============================================================================
# AI Provider (Required - Choose at least one)
# ==============================================================================

# OpenAI (Get API key from: https://platform.openai.com/api-keys)
OPENAI_API_KEY=sk-your-api-key-here

# OR Ollama (Install from: https://ollama.ai - no key needed)

# ==============================================================================
# MCP Server Configuration (Optional - add only what you need)
# ==============================================================================

# ------------------------------------------------------------------------------
# SAP ABAP ADT MCP Server (port 3234)
# ------------------------------------------------------------------------------
# Provides access to ABAP Development Tools (ADT) for retrieving ABAP source
# code, table structures, and development objects.
#
# Required credentials:
SAP_URL=https://your-sap-system.com:8000
SAP_USERNAME=your_sap_username
SAP_PASSWORD=your_sap_password
SAP_CLIENT=100
SAP_LANGUAGE=en
# Set to 0 to allow self-signed certificates (development only)
TLS_REJECT_UNAUTHORIZED=0

# ------------------------------------------------------------------------------
# SAP Notes MCP Server (port 3123)
# ------------------------------------------------------------------------------
# Provides access to official SAP Notes (knowledge base, bug fixes, patches).
# Requires S-User SAP Passport certificate (.pfx file).
#
# To obtain certificate:
# 1. Visit: https://launchpad.support.sap.com/#/user/certificate
# 2. Download your certificate
# 3. Place it in ./certs/sap.pfx
#
# Required credentials:
PFX_PATH=/app/certs/sap.pfx
PFX_PASSPHRASE=your_certificate_passphrase
HTTP_PORT=3123

# Optional: Access token for HTTP server authentication
# Generate with: openssl rand -base64 32
ACCESS_TOKEN=generate_random_secure_token_here

# ------------------------------------------------------------------------------
# S4/HANA OData MCP Server (port 3124)
# ------------------------------------------------------------------------------
# Provides access to S/4HANA OData services with direct credentials.
# No BTP or OAuth required - uses simple destination configuration.
#
# Setup guide: https://github.com/marianfoo/btp-sap-odata-to-mcp-server
#
# Required credentials:
SAP_DESTINATION_NAME=S4

# Destinations Configuration (JSON array with connection details)
# Format: [{"name":"NAME","url":"URL","username":"USER","password":"PASS"}]
# Example:
# destinations=[{"name":"S4","url":"https://your-sap-system.com:50001","username":"YOUR_USER","password":"YOUR_PASS"}]
#
destinations=[{"name":"S4","url":"https://your-sap-system.com:50001","username":"your_username","password":"your_password"}]

# MCP Tool Registry Type
# Options: 'flat' or 'hierarchical' (hierarchical groups tools by service)
MCP_TOOL_REGISTRY_TYPE=hierarchical

# Logging Level
# Options: 'error', 'warn', 'info', 'debug'
LOG_LEVEL=info

# Whether to disable ReadEntity tool registration (for large datasets)
# Set to 'true' to disable, leave unset or 'false' to enable
# DISABLE_READ_ENTITY_TOOL=false

# OData Service Discovery Configuration

# Method 1: Allow all services (use * or 'true')
ODATA_ALLOW_ALL=true

# Method 2: Specify service patterns (supports glob patterns)
# Comma-separated list of patterns to include
# Uncomment and modify to filter specific services:
# ODATA_SERVICE_PATTERNS=*TASKPROCESSING*,*BOOK*,*FLIGHT*,*TRAVEL*,*ZBP*

# Exclusion patterns (services to exclude even if they match inclusion patterns)
ODATA_EXCLUSION_PATTERNS=*_TEST*,*_TEMP*

# Maximum number of services to discover (prevents system overload)
ODATA_MAX_SERVICES=50

# ------------------------------------------------------------------------------
# SAP Docs MCP Server (port 3122)
# ------------------------------------------------------------------------------
# Provides access to official SAP Help/Docs and SAP Community content.
# No credentials needed - uses public SAP documentation.
#
MCP_PORT=3122
```

## Server Status Matrix

| Server | Port | Credentials Required | Always Available |
|--------|------|---------------------|------------------|
| SAP Docs | 3122 | ❌ None | ✅ Yes |
| SAP Notes | 3123 | ✅ S-User Certificate | ❌ No |
| S4/HANA OData | 3124 | ✅ SAP System Credentials | ❌ No |
| ABAP ADT | 3234 | ✅ SAP System Access | ❌ No |

## Minimal Setup (SAP Docs Only)

If you just want to try out MCP servers without SAP system access:

```bash
# Assuming you already have LibreChat core .env configured
# (see: https://www.librechat.ai/docs/configuration/dotenv)

# AI Provider (required - choose one)
OPENAI_API_KEY=sk-your-key-here
# OR use Ollama (no key needed)

# SAP Docs MCP Server (always available - no credentials)
MCP_PORT=3122
```

This gives you access to SAP documentation and community content without needing any SAP system credentials. Perfect for testing!

## Generating Secure Keys

For optional MCP server access tokens:

```bash
# For ACCESS_TOKEN (SAP Notes server)
openssl rand -base64 32
```

**Note**: For LibreChat core keys (JWT_SECRET, CREDS_KEY, etc.), see the [official documentation](https://www.librechat.ai/docs/configuration/dotenv#required).

## Getting Credentials

### SAP System Access (ABAP ADT)
Contact your SAP Basis administrator to get:
- System URL
- Username and password
- Client number
- Language code

### S-User Certificate (SAP Notes)
1. Visit [SAP Support Portal](https://launchpad.support.sap.com/)
2. Navigate to User → Certificate
3. Download certificate (.pfx format)
4. Save password securely

### S/4HANA System Credentials (S/4HANA OData)
Contact your SAP Basis administrator to get:
- System URL (including port, e.g., https://system.com:50001)
- Username and password
- Destination name (can be any identifier, e.g., "S4")

## Troubleshooting

### Missing Environment Variables

If you see errors about missing variables:

1. **Check .env file exists**: `ls -la .env`
2. **Verify file is sourced**: `docker compose config` (should show your values)
3. **Restart containers**: `docker compose restart`

### Invalid Credentials

If authentication fails:

1. **ABAP ADT**: Test connection directly:
   ```bash
   curl -u USERNAME:PASSWORD "https://your-sap-system.com:8000/sap/bc/adt/discovery"
   ```

2. **SAP Notes**: Verify certificate:
   ```bash
   openssl pkcs12 -info -in certs/sap.pfx -noout
   ```

3. **S4/HANA**: Validate JSON format and test connection:
   ```bash
   # Validate JSON format
   echo $destinations | jq .
   
   # Test S/4HANA connection
   curl -k -u USERNAME:PASSWORD "https://your-system.com:50001/sap/opu/odata/iwfnd/catalogservice;v=2/ServiceCollection"
   ```

### Certificate Permissions

If certificate can't be read:

```bash
chmod 644 certs/sap.pfx
chown 1000:1000 certs/sap.pfx  # Match Docker UID/GID
```

## Security Best Practices

1. ✅ **Never commit .env to git** - It's already in .gitignore
2. ✅ **Use strong, unique passwords** for each service
3. ✅ **Rotate credentials regularly** (every 90 days recommended)
4. ✅ **Limit certificate access** with proper file permissions
5. ✅ **Use separate credentials** for dev/test/prod environments
6. ✅ **Enable TLS in production** (set TLS_REJECT_UNAUTHORIZED=1)

## Reference

For more details, see:
- [MCP_SETUP_GUIDE.md](./MCP_SETUP_GUIDE.md) - Complete setup guide
- [LibreChat Environment Configuration](https://www.librechat.ai/docs/configuration/dotenv)
- [Docker Compose Environment Files](https://docs.docker.com/compose/environment-variables/)

