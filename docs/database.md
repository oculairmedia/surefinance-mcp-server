# Database Integration

The SureFinance MCP server connects to the shared PostgreSQL database used by the SureFinance Rails application.

## Configuration

Set the `DATABASE_URL` environment variable to point to the SureFinance database. Additional optional variables:

- `DB_POOL`: Connection pool size (default: 5)
- `DB_TIMEOUT`: Connection timeout in milliseconds (default: 5000)

## Models

ActiveRecord models are provided for accounts, transactions, budgets, categories, holdings, and related data structures.
