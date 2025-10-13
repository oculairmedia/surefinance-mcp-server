# Fast-MCP Migration Guide

## Executive Summary

This guide provides complete instructions for migrating the SureFinance MCP Server from custom REST endpoints to the **fast-mcp** gem, which provides proper MCP HTTP transport with JSON-RPC 2.0 support.

**Current Status:** Working REST API at `/tools/list` and `/tools/call`
**Target:** MCP-compliant JSON-RPC 2.0 server at `/mcp`
**Reason:** MCP HTTP transport requires JSON-RPC 2.0, not REST endpoints

---

## Table of Contents

1. [Understanding the Current Implementation](#1-understanding-the-current-implementation)
2. [Understanding Fast-MCP](#2-understanding-fast-mcp)
3. [Migration Strategy](#3-migration-strategy)
4. [Step-by-Step Migration](#4-step-by-step-migration)
5. [Tool Conversion Examples](#5-tool-conversion-examples)
6. [Testing the Migration](#6-testing-the-migration)
7. [Rollback Plan](#7-rollback-plan)
8. [Additional Resources](#8-additional-resources)

---

## 1. Understanding the Current Implementation

### Architecture Overview

```
Current Stack:
├── Rack/Puma HTTP Server
├── Custom JSON-RPC-like routing
├── Custom Tool Registry
├── Custom Resource Registry
├── ActiveRecord Models (SureFinance DB)
└── Authentication (disabled for single-user)
```

### Key Files

| File | Purpose | Keep/Replace |
|------|---------|--------------|
| `lib/surefinance_mcp/server.rb` | Main server, Rack app | **Replace** |
| `lib/surefinance_mcp/tools/registry.rb` | Tool registration | **Replace** |
| `lib/surefinance_mcp/tools/handlers/*.rb` | Tool implementations | **Convert** |
| `lib/surefinance_mcp/models/*.rb` | Database models | **Keep** |
| `lib/surefinance_mcp/database.rb` | DB connection | **Keep** |
| `lib/surefinance_mcp/authentication.rb` | Auth (disabled) | **Remove** |

### Current API Behavior

**List Tools:**
```bash
GET /tools/list
Response: {"tools": [{...}]}
```

**Call Tool:**
```bash
POST /tools/call
Body: {"name": "get_accounts", "arguments": {}}
Response: {"accounts": [...]}
```

### Database Connection

The server connects to SureFinance's PostgreSQL database:
- **Host:** `sure-finance-db-1:5432` (Docker network)
- **Database:** `sure_production`
- **Credentials:** In `.env` file
- **Family ID:** `87925f63-2ee1-46f8-bebd-ddab3b26e0cd` (hardcoded for single user)

---

## 2. Understanding Fast-MCP

### What Fast-MCP Provides

Fast-MCP is a Ruby gem that implements the Model Context Protocol with proper JSON-RPC 2.0 support:

```ruby
require 'fast_mcp'

# Create server
server = FastMcp::Server.new(name: 'surefinance-mcp', version: '1.0.0')

# Define a tool
class MyTool < FastMcp::Tool
  description "My tool description"

  arguments do
    required(:arg1).filled(:string).description("First argument")
  end

  def call(arg1:)
    # Tool logic here
    { result: "success" }
  end
end

# Register tool
server.register_tool(MyTool)

# Mount in Rack
use FastMcp::RackAdapter, server: server
```

### MCP Protocol Format

**JSON-RPC 2.0 Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/list",
  "params": {}
}
```

**JSON-RPC 2.0 Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "tools": [...]
  }
}
```

### Key Differences

| Feature | Current | Fast-MCP |
|---------|---------|----------|
| Protocol | Custom REST | JSON-RPC 2.0 |
| Endpoint | `/tools/list` | `/mcp` (method: "tools/list") |
| Tool Definition | Custom classes | `FastMcp::Tool` subclasses |
| Schema Validation | Manual | Built-in (dry-schema) |
| Resources | Custom | `FastMcp::Resource` |

---

## 3. Migration Strategy

### Phase 1: Preparation (1-2 hours)
1. Review fast-mcp documentation
2. Audit existing tools and their arguments
3. Create migration checklist
4. Set up testing environment

### Phase 2: Core Migration (4-6 hours)
1. Update Gemfile with fast-mcp
2. Create new server.rb using FastMcp::Server
3. Convert tool definitions one by one
4. Update database model integration
5. Configure Rack middleware

### Phase 3: Testing (2-3 hours)
1. Test all tools via JSON-RPC
2. Verify database queries
3. Test with real MCP clients (Claude Code)
4. Performance testing

### Phase 4: Deployment (1 hour)
1. Update docker-compose.yml
2. Update documentation
3. Deploy to production
4. Monitor logs

**Total Estimated Time:** 8-12 hours

---

## 4. Step-by-Step Migration

### Step 1: Update Dependencies

**File:** `Gemfile`

```ruby
# frozen_string_literal: true

source "https://rubygems.org"

ruby "3.4.4"

# MCP SDK - fast-mcp for HTTP transport
gem "fast-mcp", git: "https://github.com/yjacquin/fast-mcp.git"

# Database
gem "pg", "~> 1.5"
gem "activerecord", "~> 8.0"

# JSON handling
gem "oj", "~> 3.16"

# Environment variables
gem "dotenv", "~> 3.1"

group :development, :test do
  gem "debug", "~> 1.9"
  gem "rspec", "~> 3.13"
end
```

**Update Gemfile.lock:**
```bash
docker run --rm -v $(pwd):/app -w /app ruby:3.4.4-alpine sh -c \
  "apk add --no-cache build-base libpq-dev git yaml-dev && bundle lock"
```

### Step 2: Create New Server

**File:** `lib/surefinance_mcp/server.rb`

```ruby
# frozen_string_literal: true

require "fast_mcp"

module SurefinanceMCP
  class Server
    attr_reader :mcp_server

    def initialize(logger: SurefinanceMCP.logger)
      @logger = logger
      @database = Database.build(logger: @logger)
      @family_id = ENV.fetch("DEFAULT_FAMILY_ID", "87925f63-2ee1-46f8-bebd-ddab3b26e0cd")

      # Create Fast-MCP server
      @mcp_server = FastMcp::Server.new(
        name: "surefinance-mcp",
        version: "1.0.0"
      )

      # Register all tools
      register_tools
    end

    def app
      # Create Rack application
      Rack::Builder.new do
        # Logging
        use Rack::CommonLogger, @logger

        # Mount Fast-MCP at /mcp endpoint
        map "/mcp" do
          run FastMcp::RackAdapter.new(server: @mcp_server)
        end

        # Health check endpoint
        map "/health" do
          run ->(env) {
            [200, {"Content-Type" => "application/json"}, ['{"status":"ok"}']]
          }
        end
      end
    end

    def start(host: "0.0.0.0", port: 3500)
      @logger.info("Starting SureFinance MCP server on #{host}:#{port}")

      require "puma"
      Puma::Server.new(app).tap do |server|
        server.add_tcp_listener(host, port)
        server.run.join
      end
    end

    private

    attr_reader :logger, :database, :family_id

    def register_tools
      # Register all tool classes
      [
        Tools::GetAccounts,
        Tools::GetAccountBalanceHistory,
        Tools::GetTransactions,
        Tools::SearchTransactions,
        Tools::GetBudgets,
        Tools::GetCategories
      ].each do |tool_class|
        @mcp_server.register_tool(tool_class)
      end
    end
  end
end
```

### Step 3: Convert Tools to Fast-MCP Format

**Example: GetAccounts Tool**

**Old Format** (`lib/surefinance_mcp/tools/handlers/get_accounts.rb`):

```ruby
module SurefinanceMCP
  module Tools
    class GetAccounts
      def self.schema
        {
          name: "get_accounts",
          description: "List all accounts with current balances",
          parameters: {
            type: "object",
            properties: {
              updated_since: { type: "string", format: "date-time" }
            },
            additionalProperties: false
          }
        }
      end

      def self.call(updated_since: nil, auth:)
        family_id = auth[:family_id]
        accounts = Account.where(family_id: family_id)
        accounts = accounts.where("updated_at > ?", updated_since) if updated_since

        { accounts: accounts.map { |a| serialize_account(a) } }
      end

      def self.serialize_account(account)
        {
          id: account.id,
          name: account.name,
          balance: account.balance.to_s,
          currency: account.currency
        }
      end
    end
  end
end
```

**New Format** (Fast-MCP):

```ruby
# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    class GetAccounts < FastMcp::Tool
      description "List all accounts with current balances"

      # Define tool arguments using dry-schema
      arguments do
        optional(:updated_since).filled(:string).description("Filter accounts updated after this timestamp (ISO 8601)")
      end

      # The call method receives validated arguments
      def call(updated_since: nil)
        # Get family_id from server context
        family_id = server_context[:family_id]

        # Query database
        accounts = Account.where(family_id: family_id)
        accounts = accounts.where("updated_at > ?", updated_since) if updated_since

        # Return data
        {
          accounts: accounts.map do |account|
            {
              id: account.id,
              name: account.name,
              balance: account.balance.to_s,
              currency: account.currency
            }
          end
        }
      end

      private

      # Access to server context (family_id, etc.)
      def server_context
        @server_context ||= {
          family_id: ENV.fetch("DEFAULT_FAMILY_ID", "87925f63-2ee1-46f8-bebd-ddab3b26e0cd")
        }
      end
    end
  end
end
```

**Key Changes:**
1. Inherit from `FastMcp::Tool` instead of plain class
2. Use `arguments do` block with dry-schema syntax
3. Access `server_context` for family_id
4. Return plain hash (Fast-MCP handles JSON-RPC wrapping)

### Step 4: Update All Tools

Convert each tool following the same pattern:

1. **GetAccountBalanceHistory** - Similar to GetAccounts
2. **GetTransactions** - Has more complex arguments (dates, limits)
3. **SearchTransactions** - Has query string argument
4. **GetBudgets** - Simple, like GetAccounts
5. **GetCategories** - Simple, like GetAccounts

**Complex Arguments Example (GetTransactions):**

```ruby
class GetTransactions < FastMcp::Tool
  description "Retrieve transactions with optional filters"

  arguments do
    optional(:account_id).filled(:string).description("Filter by account ID")
    optional(:start_date).filled(:string).description("Start date (YYYY-MM-DD)")
    optional(:end_date).filled(:string).description("End date (YYYY-MM-DD)")
    optional(:limit).filled(:integer).description("Maximum number of transactions (1-500)")
  end

  def call(account_id: nil, start_date: nil, end_date: nil, limit: 100)
    family_id = server_context[:family_id]

    # Build query
    query = Transaction.joins(:account).where(accounts: { family_id: family_id })
    query = query.where(account_id: account_id) if account_id
    query = query.where("date >= ?", start_date) if start_date
    query = query.where("date <= ?", end_date) if end_date
    query = query.limit([limit.to_i, 500].min)

    {
      transactions: query.map do |txn|
        {
          id: txn.id,
          date: txn.date.iso8601,
          amount: txn.amount.to_s,
          name: txn.name,
          category: txn.category&.name
        }
      end
    }
  end

  private

  def server_context
    @server_context ||= {
      family_id: ENV.fetch("DEFAULT_FAMILY_ID")
    }
  end
end
```

### Step 5: Update Main Entry Point

**File:** `lib/surefinance_mcp.rb`

```ruby
# frozen_string_literal: true

require "bundler/setup"
require "dotenv/load"
require "logger"
require "fast_mcp"

# Load all our files
require_relative "surefinance_mcp/database"
require_relative "surefinance_mcp/models"
require_relative "surefinance_mcp/tools/get_accounts"
require_relative "surefinance_mcp/tools/get_account_balance_history"
require_relative "surefinance_mcp/tools/get_transactions"
require_relative "surefinance_mcp/tools/search_transactions"
require_relative "surefinance_mcp/tools/get_budgets"
require_relative "surefinance_mcp/tools/get_categories"
require_relative "surefinance_mcp/server"

module SurefinanceMCP
  class << self
    def logger
      @logger ||= Logger.new($stdout, level: log_level, formatter: log_formatter)
    end

    def start
      server.start
    end

    def server
      @server ||= Server.new(logger: logger)
    end

    private

    def log_level
      level = ENV.fetch("LOG_LEVEL", "info").to_s.downcase
      Logger.const_get(level.upcase)
    rescue NameError
      Logger::INFO
    end

    def log_formatter
      format = ENV.fetch("LOG_FORMAT", "json").to_s
      return json_formatter if format.casecmp("json").zero?

      proc do |severity, datetime, progname, message|
        "#{datetime.utc.iso8601} #{severity} #{progname}: #{message}\n"
      end
    end

    def json_formatter
      require "oj"
      proc do |severity, datetime, progname, message|
        Oj.dump(
          severity: severity,
          timestamp: datetime.utc.iso8601,
          progname: progname,
          message: message
        ) + "\n"
      end
    end
  end
end

# Start the server when this file is run directly
SurefinanceMCP.start if __FILE__ == $PROGRAM_NAME
```

### Step 6: Update Docker Configuration

**File:** `Dockerfile`

```dockerfile
FROM ruby:3.4.4-alpine

WORKDIR /app

# Install dependencies
RUN apk add --no-cache build-base libpq-dev git yaml-dev

# Copy Gemfiles
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Copy application code
COPY . .

# Start server
CMD ["bundle", "exec", "ruby", "lib/surefinance_mcp.rb"]
```

**File:** `docker-compose.yml`

```yaml
version: "3.9"

services:
  surefinance-mcp:
    build: .
    ports:
      - "4332:3500"
    env_file:
      - .env
    environment:
      MCP_SERVER_HOST: 0.0.0.0
      MCP_SERVER_PORT: 3500
      MCP_SERVER_ENV: development
      LOG_LEVEL: info
      LOG_FORMAT: json
    networks:
      - sure-finance_sure_net
      - default

networks:
  sure-finance_sure_net:
    external: true
```

---

## 5. Tool Conversion Examples

### Example 1: Simple Tool (GetCategories)

**Before:**
```ruby
class GetCategories
  def self.schema
    {
      name: "get_categories",
      description: "List categories with hierarchy",
      parameters: {
        type: "object",
        properties: {
          parent_id: { type: "string" }
        }
      }
    }
  end

  def self.call(parent_id: nil, auth:)
    family_id = auth[:family_id]
    categories = Category.where(family_id: family_id)
    categories = categories.where(parent_id: parent_id) if parent_id

    categories.map do |c|
      { id: c.id, name: c.name, parent_id: c.parent_id }
    end
  end
end
```

**After:**
```ruby
class GetCategories < FastMcp::Tool
  description "List categories with hierarchy"

  arguments do
    optional(:parent_id).filled(:string).description("Filter by parent category ID")
  end

  def call(parent_id: nil)
    family_id = ENV.fetch("DEFAULT_FAMILY_ID")

    categories = Category.where(family_id: family_id)
    categories = categories.where(parent_id: parent_id) if parent_id

    categories.map do |category|
      {
        id: category.id,
        name: category.name,
        parent_id: category.parent_id
      }
    end
  end
end
```

### Example 2: Complex Nested Arguments (Hypothetical)

If you need nested arguments:

```ruby
class CreateTransaction < FastMcp::Tool
  description "Create a new transaction"

  arguments do
    required(:account_id).filled(:string).description("Account ID")
    required(:amount).filled(:decimal).description("Transaction amount")
    required(:date).filled(:string).description("Transaction date (YYYY-MM-DD)")
    optional(:category_id).filled(:string).description("Category ID")

    optional(:metadata).description("Additional metadata").hash do
      optional(:merchant).filled(:string).description("Merchant name")
      optional(:tags).array(:string).description("Transaction tags")
    end
  end

  def call(account_id:, amount:, date:, category_id: nil, metadata: {})
    family_id = ENV.fetch("DEFAULT_FAMILY_ID")

    Transaction.create!(
      account_id: account_id,
      amount: amount,
      date: Date.parse(date),
      category_id: category_id,
      # ... additional fields
    )

    { success: true, transaction_id: transaction.id }
  end
end
```

### Example 3: Error Handling

```ruby
class GetAccountBalanceHistory < FastMcp::Tool
  description "Retrieve balance history for a specific account"

  arguments do
    required(:account_id).filled(:string).description("Account ID")
    optional(:range).filled(:string, included_in?: ["30d", "90d", "1y"]).description("Time range")
  end

  def call(account_id:, range: "30d")
    family_id = ENV.fetch("DEFAULT_FAMILY_ID")

    # Find account
    account = Account.find_by(id: account_id, family_id: family_id)
    raise ArgumentError, "Account not found" unless account

    # Calculate date range
    days = case range
    when "30d" then 30
    when "90d" then 90
    when "1y" then 365
    end

    start_date = Date.today - days

    # Get balances
    balances = AccountBalanceHistory.where(
      account_id: account_id,
      date: start_date..Date.today
    ).order(:date)

    {
      account_id: account_id,
      account_name: account.name,
      range: range,
      balances: balances.map do |b|
        { date: b.date.iso8601, balance: b.balance.to_s }
      end
    }
  rescue ArgumentError => e
    { error: e.message }
  end
end
```

---

## 6. Testing the Migration

### Manual Testing

**Test 1: List Tools**

```bash
curl -X POST http://localhost:4332/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/list"
  }' | jq .
```

Expected response:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "tools": [
      {
        "name": "get_accounts",
        "description": "List all accounts with current balances",
        "inputSchema": {
          "type": "object",
          "properties": {
            "updated_since": {
              "type": "string",
              "description": "Filter accounts updated after this timestamp (ISO 8601)"
            }
          }
        }
      }
      // ... more tools
    ]
  }
}
```

**Test 2: Call Tool**

```bash
curl -X POST http://localhost:4332/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "get_accounts",
      "arguments": {}
    }
  }' | jq .
```

Expected response:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{\"accounts\":[...]}"
      }
    ]
  }
}
```

**Test 3: Call Tool with Arguments**

```bash
curl -X POST http://localhost:4332/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "get_transactions",
      "arguments": {
        "limit": 10
      }
    }
  }' | jq .
```

### Automated Testing with RSpec

**File:** `spec/integration/mcp_server_spec.rb`

```ruby
require "spec_helper"
require "rack/test"

RSpec.describe "MCP Server Integration" do
  include Rack::Test::Methods

  def app
    SurefinanceMCP.server.app
  end

  describe "POST /mcp" do
    context "tools/list method" do
      it "returns all available tools" do
        post "/mcp", {
          jsonrpc: "2.0",
          id: 1,
          method: "tools/list"
        }.to_json, "CONTENT_TYPE" => "application/json"

        expect(last_response.status).to eq(200)

        json = JSON.parse(last_response.body)
        expect(json["jsonrpc"]).to eq("2.0")
        expect(json["id"]).to eq(1)
        expect(json["result"]["tools"]).to be_an(Array)
        expect(json["result"]["tools"].length).to eq(6)
      end
    end

    context "tools/call method" do
      it "calls get_accounts tool" do
        post "/mcp", {
          jsonrpc: "2.0",
          id: 2,
          method: "tools/call",
          params: {
            name: "get_accounts",
            arguments: {}
          }
        }.to_json, "CONTENT_TYPE" => "application/json"

        expect(last_response.status).to eq(200)

        json = JSON.parse(last_response.body)
        expect(json["jsonrpc"]).to eq("2.0")
        expect(json["result"]["content"]).to be_an(Array)
      end

      it "validates required arguments" do
        post "/mcp", {
          jsonrpc: "2.0",
          id: 3,
          method: "tools/call",
          params: {
            name: "get_account_balance_history",
            arguments: {}  # Missing required account_id
          }
        }.to_json, "CONTENT_TYPE" => "application/json"

        expect(last_response.status).to eq(200)

        json = JSON.parse(last_response.body)
        expect(json["error"]).to be_present
      end
    end
  end

  describe "GET /health" do
    it "returns ok status" do
      get "/health"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq('{"status":"ok"}')
    end
  end
end
```

### Testing with Claude Code

**Add to Claude Code:**
```bash
claude mcp add --transport http surefinance-mcp http://192.168.50.90:4332/mcp
```

**Test in Claude:**
```
User: "Show me my accounts"
Claude: [Uses get_accounts tool]

User: "What were my transactions last month?"
Claude: [Uses get_transactions tool with date filters]
```

---

## 7. Rollback Plan

If the migration fails, you can rollback to the current working state.

### Git Branches

Before starting migration:
```bash
git checkout -b feature/fast-mcp-migration
git add -A
git commit -m "Checkpoint: Pre-migration state"
```

### Rollback Steps

1. **Stop the new container:**
   ```bash
   docker compose down
   ```

2. **Checkout previous commit:**
   ```bash
   git checkout HEAD~1
   ```

3. **Rebuild and restart:**
   ```bash
   docker compose up -d --build
   ```

4. **Verify:**
   ```bash
   curl http://localhost:4332/tools/list
   ```

### Migration Checklist

- [ ] Create feature branch
- [ ] Checkpoint commit with current state
- [ ] Update Gemfile
- [ ] Convert GetAccounts tool
- [ ] Test GetAccounts
- [ ] Convert remaining tools one by one
- [ ] Test each tool as you go
- [ ] Integration test all tools
- [ ] Test with Claude Code
- [ ] Update documentation
- [ ] Merge to main

---

## 8. Additional Resources

### Fast-MCP Documentation

- **GitHub:** https://github.com/yjacquin/fast-mcp
- **Examples:** Check `/examples` directory in repo
- **Discord:** https://discord.gg/9HHfAtY3HF

### MCP Protocol Specification

- **Official Docs:** https://modelcontextprotocol.io
- **JSON-RPC 2.0:** https://www.jsonrpc.org/specification

### Dry-Schema (Argument Validation)

- **Documentation:** https://dry-rb.org/gems/dry-schema
- **Types:** https://dry-rb.org/gems/dry-types

### SureFinance Database Schema

**Key Tables:**
- `families` - Family/household entity
- `accounts` - Bank accounts, investments, etc.
- `entries` - Double-entry accounting entries
- `transactions` - Imported transactions
- `categories` - Transaction categories
- `budgets` - Budget definitions
- `budget_periods` - Budget period tracking

**Important:** All queries must filter by `family_id`

---

## Appendix A: Complete Tool Conversion Template

```ruby
# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    class ToolName < FastMcp::Tool
      # Tool description (required)
      description "Clear description of what this tool does"

      # Arguments definition (use dry-schema syntax)
      arguments do
        # Required string argument
        required(:arg1).filled(:string).description("Description of arg1")

        # Optional integer with validation
        optional(:arg2).filled(:integer).description("Description of arg2")

        # String with enum values
        optional(:arg3).filled(:string, included_in?: ["val1", "val2"]).description("Choose val1 or val2")

        # Date string
        optional(:date).filled(:string).description("Date in YYYY-MM-DD format")

        # Nested hash
        optional(:metadata).description("Metadata object").hash do
          optional(:key1).filled(:string)
          optional(:key2).filled(:integer)
        end
      end

      # Main call method - receives validated arguments
      def call(arg1:, arg2: nil, arg3: nil, date: nil, metadata: {})
        # Get family_id from environment
        family_id = ENV.fetch("DEFAULT_FAMILY_ID")

        # Your tool logic here
        # - Query database using ActiveRecord models
        # - Process data
        # - Return results as hash

        {
          # Your response data
        }
      rescue StandardError => e
        # Handle errors
        logger.error("Tool failed: #{e.message}")
        { error: e.message }
      end

      private

      # Helper methods
      def logger
        SurefinanceMCP.logger
      end
    end
  end
end
```

---

## Appendix B: Environment Variables Reference

**File:** `.env`

```bash
# Server Configuration
MCP_SERVER_HOST=0.0.0.0
MCP_SERVER_PORT=3500
MCP_SERVER_ENV=development

# Database Configuration (SureFinance PostgreSQL)
DATABASE_URL=postgresql://sure_user:PASSWORD@sure-finance-db-1:5432/sure_production

# Authentication (Single-user mode)
DEFAULT_FAMILY_ID=87925f63-2ee1-46f8-bebd-ddab3b26e0cd

# Logging
LOG_LEVEL=info
LOG_FORMAT=json
```

---

## Appendix C: Troubleshooting Guide

### Issue: "uninitialized constant FastMcp"

**Cause:** Gem not installed or not required properly

**Solution:**
```bash
bundle install
# or
docker compose down && docker compose up -d --build
```

### Issue: "Validation failed" when calling tool

**Cause:** Arguments don't match dry-schema definition

**Solution:** Check the tool's `arguments` block matches the incoming params

### Issue: "Family not found" or empty results

**Cause:** Incorrect `family_id` or database connection issue

**Solution:**
1. Check `.env` has correct `DEFAULT_FAMILY_ID`
2. Verify database connection in logs
3. Check `families` table in database

### Issue: JSON-RPC error response

**Cause:** Tool raised an exception

**Solution:** Check logs for stack trace, add error handling in tool

### Issue: Tool not listed in tools/list

**Cause:** Tool not registered with server

**Solution:** Add tool class to `register_tools` method in `server.rb`

---

## Appendix D: Performance Considerations

### Database Query Optimization

1. **Add indexes** for common queries:
   ```sql
   CREATE INDEX idx_accounts_family_id ON accounts(family_id);
   CREATE INDEX idx_transactions_account_date ON transactions(account_id, date);
   ```

2. **Use ActiveRecord includes** to avoid N+1:
   ```ruby
   Transaction.includes(:account, :category).where(...)
   ```

3. **Limit result sizes:**
   ```ruby
   query.limit(500) # Maximum 500 results
   ```

### Caching Strategies

For frequently accessed data:

```ruby
class GetCategories < FastMcp::Tool
  def call
    family_id = ENV.fetch("DEFAULT_FAMILY_ID")

    # Cache categories for 5 minutes
    Rails.cache.fetch("categories:#{family_id}", expires_in: 5.minutes) do
      Category.where(family_id: family_id).to_a
    end
  end
end
```

---

## Appendix E: Security Considerations

### Current Security Model

- **No authentication** (single-user mode)
- **Hardcoded family_id** in environment
- **No rate limiting**
- **No request validation** beyond schema

### Future Security Enhancements

1. **Add API key authentication:**
   ```ruby
   # In server.rb
   use Rack::Auth::Basic do |username, password|
     password == ENV['MCP_API_KEY']
   end
   ```

2. **Add rate limiting:**
   ```ruby
   use Rack::Attack

   Rack::Attack.throttle("mcp/ip", limit: 60, period: 1.minute) do |req|
     req.ip if req.path == "/mcp"
   end
   ```

3. **Enable multi-family support:**
   - Add authentication header with family_id
   - Validate family_id against database
   - Pass family_id through server_context

---

## Summary

This migration guide provides everything needed to convert the SureFinance MCP Server from custom REST endpoints to Fast-MCP with proper JSON-RPC 2.0 support.

**Key Takeaways:**
1. Fast-MCP handles JSON-RPC protocol complexity
2. Tool conversion is straightforward with templates
3. Database models remain unchanged
4. Testing is crucial - test each tool as you convert
5. Have a rollback plan ready

**Estimated Migration Time:** 8-12 hours for experienced Ruby developer

**Questions?** Refer to Fast-MCP documentation or MCP Discord community.

---

**End of Migration Guide**
