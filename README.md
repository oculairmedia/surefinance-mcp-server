# SureFinance MCP Server

Model Context Protocol (MCP) server for SureFinance financial data integration.

## Overview

This MCP server provides programmatic access to SureFinance financial data through standardized tools and resources. It enables AI assistants and other MCP clients to query accounts, transactions, budgets, and analytics.

## Technology Stack

- **Language:** Ruby 3.4.4
- **MCP SDK:** [Official Ruby SDK](https://github.com/modelcontextprotocol/ruby-sdk)
- **Transport:** HTTP/HTTPS
- **Database:** PostgreSQL (shared with SureFinance Rails app)

## Project Structure

```
surefinance-mcp-server/
├── lib/
│   ├── surefinance_mcp/
│   │   ├── server.rb        # Main MCP server
│   │   ├── tools/           # MCP tool implementations
│   │   ├── resources/       # MCP resource handlers
│   │   └── models/          # Data models
│   └── surefinance_mcp.rb   # Main entry point
├── config/
│   ├── database.yml         # Database configuration
│   └── server.yml           # Server configuration
├── Gemfile
├── Dockerfile
├── docker-compose.yml
└── README.md
```

## Quick Start

```bash
# Install dependencies
bundle install

# Set up environment
cp .env.example .env
# Edit .env with your configuration

# Run the server
bundle exec ruby lib/surefinance_mcp.rb
```

## Docker Deployment

```bash
# Build and run with Docker Compose
docker-compose up -d

# View logs
docker-compose logs -f
```

## MCP Tools

### Account Tools
- `get_accounts` - List all accounts with current balances
- `get_account_balance_history` - Time series balance data for charts

### Transaction Tools
- `get_transactions` - Query transactions with filters
- `search_transactions` - Full-text search across transactions

### Budget Tools
- `get_budgets` - List budgets with spending analysis

### Category Tools
- `get_categories` - List transaction categories and hierarchies

## MCP Resources

- `surefinance://accounts/{id}` - Account details with balance history
- `surefinance://transactions/{id}` - Transaction details
- `surefinance://budgets/{id}` - Budget details with spending breakdown
- `surefinance://holdings/{id}` - Investment holding details

## Authentication

The server supports authentication via:
- API keys (for trusted clients)
- JWT tokens (for programmatic access)

See [Authentication Guide](docs/authentication.md) for details.

## Development

```bash
# Run tests
bundle exec rspec

# Run linter
bundle exec rubocop

# Auto-fix linting issues
bundle exec rubocop -a
```

## Documentation

Full documentation is available in [BookStack](https://docs.oculair.ca/books/surefinance-mcp-server).

## Related Projects

- [SureFinance](https://github.com/maybe-finance/maybe) - Personal finance and wealth management app
- [Huly Project](https://pm.oculair.ca/workbench/agentspace/browse/SFMCP) - Project tracking

## License

MIT License - See LICENSE file for details
