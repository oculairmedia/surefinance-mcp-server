# AGENT.md

This file provides guidance to AI agents (Claude Code, etc.) when working with code in this repository.

## Project Overview

**SureFinance MCP Server** - A Model Context Protocol server providing access to SureFinance financial data through standardized MCP tools.

### Technology Stack
- **Language**: Ruby 3.4.4
- **Framework**: Rack 3.x with Puma web server
- **MCP SDK**: fast-mcp (git: https://github.com/yjacquin/fast-mcp.git)
- **Database**: PostgreSQL via ActiveRecord 8.0
- **Deployment**: Docker containers

## Critical Configuration Requirements

### MCP Endpoint Configuration

**REQUIREMENT**: The MCP server MUST respond at `/mcp` directly, not `/mcp/messages`.

**Implementation** (in `lib/surefinance_mcp/server.rb`):
```ruby
FastMcp.rack_middleware(
  health_app,
  name: "surefinance-mcp",
  version: DEFAULT_VERSION,
  path_prefix: "",        # No prefix - important!
  messages_route: "mcp",  # Route is "mcp", making full path /mcp
  logger: server_logger,
  localhost_only: false,
  allowed_origins: []
) do |mcp_server|
  # Tool registration...
end
```

**Why This Matters**:
- MCP clients expect JSON-RPC endpoints at `/mcp` by convention
- The fast-mcp gem defaults to `/mcp/messages` which breaks compatibility
- Setting `path_prefix: ""` and `messages_route: "mcp"` ensures the endpoint is at `/mcp`

**Testing the Endpoint**:
```bash
curl -X POST http://localhost:4332/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/list",
    "id": 1
  }'
```

Should return a JSON-RPC response with the list of available tools.

## Development Commands

### Docker Operations
```bash
# Build image (no cache)
docker compose build --no-cache

# Start server
docker compose up -d

# View logs
docker logs surefinance-mcp-server-surefinance-mcp-1 --tail 50

# Restart server
docker compose restart

# Stop and remove
docker compose down
```

### Testing
```bash
# Run RSpec tests
bundle exec rspec

# Integration tests
bundle exec rspec spec/integration/

# Tool-specific tests
bundle exec rspec spec/surefinance_mcp/tools/
```

## Architecture

### Server Structure
- **Entry Point**: `bin/surefinance_mcp_server`
- **Server Core**: `lib/surefinance_mcp/server.rb`
- **Configuration**: `config/server.yml` (loaded via ERB)
- **Tools**: `lib/surefinance_mcp/tools/handlers/` (each tool as FastMcp::Tool subclass)

### Tool Registration
All tools inherit from `FastMcp::Tool` and are registered in `lib/surefinance_mcp/tools/accounts_tools.rb`:
```ruby
def tools
  [
    Handlers::GetAccounts,
    Handlers::GetTransactions,
    Handlers::SearchTransactions,
    Handlers::GetAccountBalanceHistory,
    Handlers::GetBudgets,
    Handlers::GetCategories
  ]
end
```

### Database Models
Located in `lib/surefinance_mcp/models/`:
- `Family` - Top-level organization
- `Account` - Financial accounts (polymorphic association to Entry)
- `Entry` - Ledger entries (polymorphic association to Transaction)
- `Transaction` - Financial transactions
- `Budget` - Budget definitions
- `Category` - Transaction categories (nested set)

## Environment Variables

Required:
- `DATABASE_URL` - PostgreSQL connection string
- `PORT` - Server port (default: 3500, exposed as 4332)

Optional:
- `LOG_LEVEL` - Logging level (default: info)
- `LOG_FORMAT` - Log format: json or text (default: text)
- `DEFAULT_FAMILY_ID` - Default family UUID for queries
- `MCP_SERVER_ENV` - Environment mode (development, test, production)

## Common Issues

### Issue: 404 "Endpoint not found" on MCP requests
**Cause**: Incorrect `path_prefix` or `messages_route` configuration
**Solution**: Ensure `path_prefix: ""` and `messages_route: "mcp"` in server.rb

### Issue: Container not picking up code changes
**Cause**: Docker using cached image
**Solution**: Rebuild without cache: `docker compose build --no-cache`

### Issue: Database connection errors
**Cause**: DATABASE_URL not set or PostgreSQL not accessible
**Solution**: Check docker-compose.yml for correct DATABASE_URL format

## Best Practices

1. **Always rebuild Docker image after Ruby code changes**: Container doesn't mount source as volume
2. **Use bundle install locally for development**: Faster iteration than rebuilding Docker
3. **Test endpoint changes with curl**: Verify JSON-RPC compliance before client testing
4. **Check logs for fast-mcp messages**: The gem provides detailed debug logging
5. **Follow existing tool patterns**: All tools follow the same structure for consistency

## References

- [Fast-MCP Documentation](https://github.com/yjacquin/fast-mcp)
- [Model Context Protocol Specification](https://modelcontextprotocol.io/)
- [BUG_REPORT_AND_RESOLUTION.md](./BUG_REPORT_AND_RESOLUTION.md) - Production issues and fixes
- [FAST_MCP_MIGRATION_GUIDE.md](./FAST_MCP_MIGRATION_GUIDE.md) - Migration from custom implementation
