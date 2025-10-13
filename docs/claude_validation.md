# Claude Code Validation (Skeleton)

Purpose: Manual E2E validation using Claude Code as an MCP client.

## Add Server
```
claude mcp add --transport http surefinance-mcp http://192.168.50.90:4332/mcp
```

## Scenarios
- List tools
- Call get_accounts
- Call get_transactions with limit 10

## Observations
- [ ] Tools list contains all expected entries
- [ ] Calls succeed and return JSON payloads
- [ ] Any errors or anomalies (paste snippets)
