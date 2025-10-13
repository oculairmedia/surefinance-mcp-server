# MCP Tools Audit (Skeleton)

Purpose: Track current vs. target Fast‑MCP specs for each tool.

## Tools

### get_accounts
- Current handler: lib/surefinance_mcp/tools/handlers/get_accounts.rb
- Current REST schema: TODO
- Proposed Fast‑MCP arguments:
  - optional updated_since: string (ISO8601)
- Output shape: { accounts: [{ id, name, balance, currency }] }
- Family scoping: required (Models::Account.for_family)
- Edge cases: TODO

### get_account_balance_history
- Current handler: lib/surefinance_mcp/tools/handlers/get_account_balance_history.rb
- Current REST schema: TODO
- Proposed Fast‑MCP arguments:
  - required account_id: string
  - optional range: enum[30d, 90d, 1y]
- Output shape: { account_id, account_name, range, balances: [{ date, balance }] }
- Family scoping: required (account belongs to family)
- Edge cases: TODO

### get_transactions
- Current handler: lib/surefinance_mcp/tools/handlers/get_transactions.rb
- Current REST schema: TODO
- Proposed Fast‑MCP arguments:
  - optional account_id: string
  - optional start_date: string (YYYY‑MM‑DD)
  - optional end_date: string (YYYY‑MM‑DD)
  - optional limit: integer (max 500)
- Output shape: { transactions: [{ id, date, amount, name, category }] }
- Family scoping: required (join accounts)
- Edge cases: TODO

### search_transactions
- Current handler: lib/surefinance_mcp/tools/handlers/search_transactions.rb
- Current REST schema: TODO
- Proposed Fast‑MCP arguments:
  - required query: string (min len 2)
- Output shape: { transactions: [...] }
- Family scoping: required
- Edge cases: TODO

### get_budgets
- Current handler: lib/surefinance_mcp/tools/handlers/get_budgets.rb
- Current REST schema: TODO
- Proposed Fast‑MCP arguments: none
- Output shape: { budgets: [...] }
- Family scoping: required
- Edge cases: TODO

### get_categories
- Current handler: lib/surefinance_mcp/tools/handlers/get_categories.rb
- Current REST schema: TODO
- Proposed Fast‑MCP arguments:
  - optional parent_id: string
- Output shape: { categories: [...] }
- Family scoping: required
- Edge cases: TODO

## JSON‑RPC Examples (fill during conversion)
- tools/list: TODO
- tools/call get_accounts: TODO
