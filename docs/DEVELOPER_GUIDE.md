# SureFinance MCP Server - Developer Guide

## Table of Contents
1. [Overview](#overview)
2. [MCP Ruby SDK Integration](#mcp-ruby-sdk-integration)
3. [SureFinance Rails Integration](#surefinance-rails-integration)
4. [Implementation Roadmap](#implementation-roadmap)
5. [Authentication & Authorization](#authentication--authorization)
6. [Testing Strategy](#testing-strategy)
7. [Deployment](#deployment)

---

## Overview

The SureFinance MCP Server provides programmatic access to SureFinance financial data through the Model Context Protocol. This guide provides comprehensive context for implementing the server correctly.

### Architecture

```
┌─────────────────────────────────────────────────┐
│              MCP Client (Claude Code)           │
└────────────────┬────────────────────────────────┘
                 │ HTTP/JSON-RPC 2.0
                 ▼
┌─────────────────────────────────────────────────┐
│         SureFinance MCP Server (Ruby)           │
│  ┌───────────┐  ┌──────────┐  ┌──────────────┐ │
│  │   Tools   │  │Resources │  │  Auth Layer  │ │
│  └─────┬─────┘  └────┬─────┘  └──────┬───────┘ │
│        │             │                │         │
│  ┌─────┴─────────────┴────────────────┴───────┐ │
│  │        ActiveRecord Models (shared)        │ │
│  └──────────────────┬─────────────────────────┘ │
└────────────────────┬───────────────────────────┘
                     │ PostgreSQL
                     ▼
┌─────────────────────────────────────────────────┐
│      SureFinance Database (Rails App)           │
└─────────────────────────────────────────────────┘
```

---

## MCP Ruby SDK Integration

### Official SDK Documentation

The Ruby SDK implements the Model Context Protocol specification. Key concepts:

#### 1. Server Creation

```ruby
require "mcp"

server = MCP::Server.new(
  name: "surefinance",
  version: "1.0.0",
  instructions: "Access to SureFinance financial data",
  tools: [GetAccountsTool, GetTransactionsTool],
  resources: [AccountResource, TransactionResource],
  server_context: { family_id: current_family_id }
)
```

**Critical Points:**
- `server_context` is passed to ALL tool/resource handlers
- Use it for family scoping and authorization
- Gets populated per-request from authenticated session

#### 2. Tool Definition

The SDK supports two styles:

**Class-based (RECOMMENDED for our use case):**

```ruby
class GetAccountsTool < MCP::Tool
  description "List all accounts with current balances"

  input_schema(
    properties: {
      status: {
        type: "string",
        enum: ["active", "draft", "disabled"],
        description: "Filter by account status"
      },
      classification: {
        type: "string",
        enum: ["asset", "liability"],
        description: "Filter by classification"
      }
    }
  )

  annotations(
    title: "Get Accounts",
    read_only_hint: true,      # Does not modify data
    idempotent_hint: true,      # Same result on repeat calls
    open_world_hint: false      # Closed schema
  )

  class << self
    def call(status: nil, classification: nil, server_context:)
      family = Family.find(server_context[:family_id])
      accounts = family.accounts.visible

      # Apply filters
      accounts = accounts.where(status: status) if status
      accounts = accounts.where(classification: classification) if classification

      MCP::Tool::Response.new([{
        type: "text",
        text: accounts.map { |a| format_account(a) }.to_json
      }])
    end

    private

    def format_account(account)
      {
        id: account.id,
        name: account.name,
        balance: account.balance.to_s,
        currency: account.currency,
        classification: account.classification,
        accountable_type: account.accountable_type,
        subtype: account.subtype,
        status: account.status
      }
    end
  end
end
```

**Block-based (useful for simple tools):**

```ruby
tool = MCP::Tool.define(
  name: "ping",
  description: "Health check"
) do |args, server_context|
  MCP::Tool::Response.new([{
    type: "text",
    text: "pong"
  }])
end
```

#### 3. Resource Definition

Resources expose data via URIs:

```ruby
# Register static resource
resource = MCP::Resource.new(
  uri: "surefinance://accounts/list",
  name: "All Accounts",
  description: "Complete list of family accounts",
  mime_type: "application/json"
)

server = MCP::Server.new(
  name: "surefinance",
  resources: [resource]
)

# Dynamic resource handler
server.resources_read_handler do |params|
  family_id = params[:server_context][:family_id]
  uri = params[:uri]

  # Parse URI: surefinance://accounts/123
  if uri =~ %r{^surefinance://accounts/(\d+)$}
    account = Account.find_by(id: $1, family_id: family_id)

    [{
      uri: uri,
      mimeType: "application/json",
      text: account.to_json(
        include: {
          entries: { limit: 100 },
          balances: { limit: 30 }
        }
      )
    }]
  else
    raise MCP::Error.new(
      code: -32602,
      message: "Resource not found: #{uri}"
    )
  end
end
```

#### 4. Transport Options

**Option A: HTTP Server (RECOMMENDED for our use case)**

```ruby
require "mcp"
require "rack"
require "puma"

server = MCP::Server.new(
  name: "surefinance",
  tools: [GetAccountsTool],
  server_context: {} # Will be populated per-request
)

# Rack middleware
app = Rack::Builder.new do
  use Rack::CommonLogger
  use Rack::ContentType, "application/json"

  # Auth middleware
  use AuthenticationMiddleware

  run ->(env) {
    request = Rack::Request.new(env)

    # Inject family_id from authenticated session
    server_context = {
      family_id: request.env['authenticated_family_id'],
      user_id: request.env['authenticated_user_id']
    }

    # Handle JSON-RPC 2.0 request
    json_response = server.handle_json(
      request.body.read,
      server_context: server_context
    )

    [200, {}, [json_response]]
  }
end

Rackup::Handler::Puma.run(app, Host: "0.0.0.0", Port: 3500)
```

**Option B: Stdio Transport (for CLI tools)**

```ruby
transport = MCP::Server::Transports::StdioTransport.new(server)
transport.open
```

#### 5. Notifications

Notify clients when data changes:

```ruby
server.notify_tools_list_changed()       # Tools added/removed
server.notify_resources_list_changed()   # Resources changed
server.notify_prompts_list_changed()     # Prompts changed
```

#### 6. Custom Methods

Add non-standard JSON-RPC methods:

```ruby
server.define_custom_method(method_name: "health") do |params|
  {
    status: "healthy",
    database: ActiveRecord::Base.connected?,
    timestamp: Time.current.iso8601
  }
end
```

#### 7. Error Handling

```ruby
MCP.configure do |config|
  config.exception_reporter = ->(exception, server_context) {
    Rails.logger.error(
      "MCP Error: #{exception.message}",
      family_id: server_context[:family_id],
      backtrace: exception.backtrace.first(5)
    )

    # Report to error tracking service
    Bugsnag.notify(exception) if defined?(Bugsnag)
  }

  config.instrumentation_callback = ->(data) {
    # Log metrics
    Rails.logger.info("MCP Instrumentation", data)
  }
end
```

#### 8. Protocol Version

```ruby
configuration = MCP::Configuration.new(
  protocol_version: "2024-11-05"  # Current MCP spec version
)

server = MCP::Server.new(
  name: "surefinance",
  configuration: configuration
)
```

---

## SureFinance Rails Integration

### Critical Context: Multi-Tenancy

**SureFinance uses `Current.family` for multi-tenancy scoping.**

```ruby
# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :session

  delegate :family, to: :user, allow_nil: true

  def user
    session&.user
  end
end
```

**ALL queries MUST be scoped to family:**

```ruby
# ❌ WRONG - Exposes all families' data
Account.all

# ✅ CORRECT - Scoped to authenticated family
family = Family.find(server_context[:family_id])
family.accounts.all
```

### Core Models

#### Account Model

```ruby
class Account < ApplicationRecord
  belongs_to :family
  belongs_to :simplefin_account, optional: true

  has_many :entries, dependent: :destroy
  has_many :transactions, through: :entries
  has_many :holdings, dependent: :destroy
  has_many :balances, dependent: :destroy

  delegated_type :accountable, types: [
    "Depository",    # Checking, savings
    "Investment",    # Brokerage, retirement
    "CreditCard",    # Credit cards
    "Loan",          # Mortgages, loans
    "Property",      # Real estate
    "Vehicle",       # Cars, etc.
    "Crypto",        # Cryptocurrency
    "OtherAsset",    # Other assets
    "OtherLiability" # Other liabilities
  ]

  monetize :balance, :cash_balance

  enum :classification, {
    asset: "asset",
    liability: "liability"
  }

  enum :status, {
    active: "active",
    draft: "draft",
    disabled: "disabled",
    pending_deletion: "pending_deletion"
  }

  scope :visible, -> { where(status: ["draft", "active"]) }
  scope :assets, -> { where(classification: "asset") }
  scope :liabilities, -> { where(classification: "liability") }
end
```

**Key Methods:**
- `balance` - Current balance (Money object)
- `cash_balance` - Cash portion (for investments)
- `balance_type` - `:cash`, `:non_cash`, or `:investment`
- `current_holdings` - Current investment holdings
- `start_date` - First entry date

#### Transaction Model

```ruby
class Transaction < ApplicationRecord
  include Entryable  # Polymorphic through Entry

  belongs_to :category, optional: true
  belongs_to :merchant, optional: true

  has_many :taggings, as: :taggable
  has_many :tags, through: :taggings

  enum :kind, {
    standard: "standard",           # Regular transaction
    funds_movement: "funds_movement", # Account transfers
    cc_payment: "cc_payment",         # Credit card payment
    loan_payment: "loan_payment",     # Loan payment
    one_time: "one_time"              # One-time item
  }

  # Access via: account.transactions or family.transactions
end
```

**Entryable Pattern:**
```ruby
# Transactions are accessed through Entry (polymorphic)
Entry has_one :account
Entry belongs_to :entryable, polymorphic: true

# Query transactions:
family.entries.where(entryable_type: "Transaction")
# OR
account.transactions # (has_many through: :entries)
```

#### Family Model

```ruby
class Family < ApplicationRecord
  has_many :users
  has_many :accounts
  has_many :entries, through: :accounts
  has_many :transactions, through: :accounts
  has_many :holdings, through: :accounts
  has_many :tags
  has_many :categories
  has_many :merchants, class_name: "FamilyMerchant"
  has_many :budgets
  has_many :budget_categories, through: :budgets

  validates :locale, inclusion: { in: I18n.available_locales.map(&:to_s) }
end
```

**Key Methods:**
- `balance_sheet` - Asset/liability summary
- `income_statement` - Income/expense summary
- `oldest_entry_date` - Historical data start

#### Budget Model

```ruby
class Budget < ApplicationRecord
  belongs_to :family
  has_many :budget_categories
  has_many :categories, through: :budget_categories

  # Budgets have periods (monthly, annually, etc.)
end
```

#### Category Model

```ruby
class Category < ApplicationRecord
  belongs_to :family
  has_many :transactions

  # Categories can be hierarchical
  # Used for budget categorization
end
```

### Database Connection Strategy

**Option 1: Direct Database Connection (RECOMMENDED)**

Share the database with SureFinance Rails app:

```yaml
# config/database.yml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("DB_POOL", 5) %>
  host: <%= ENV.fetch("DB_HOST", "localhost") %>
  username: <%= ENV.fetch("DB_USER", "surefinance") %>
  password: <%= ENV.fetch("DB_PASSWORD") %>
  database: <%= ENV.fetch("DB_NAME", "surefinance_production") %>

production:
  <<: *default
```

**Pros:**
- Direct, fast access
- Reuse ActiveRecord models
- No API overhead

**Cons:**
- Tight coupling to DB schema
- Schema changes require MCP server updates

**Option 2: Copy Models (Hybrid Approach)**

Copy essential models from Rails app, keep them in sync:

```ruby
# lib/surefinance_mcp/models/account.rb
# Simplified version of Rails model
module SurefinanceMCP
  module Models
    class Account < ApplicationRecord
      self.table_name = "accounts"

      belongs_to :family
      has_many :entries
      has_many :balances

      # Only include methods needed for MCP tools
    end
  end
end
```

**Option 3: Rails API Calls**

Create internal API endpoints in Rails app:

```ruby
# In Rails app: app/controllers/internal_api/accounts_controller.rb
module InternalApi
  class AccountsController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_internal_api_key

    def index
      family = Family.find(params[:family_id])
      render json: family.accounts.visible
    end
  end
end

# In MCP server:
response = HTTP.auth("Bearer #{ENV['INTERNAL_API_KEY']}")
              .get("#{RAILS_URL}/internal_api/accounts",
                   params: { family_id: family_id })
```

**Pros:**
- Complete decoupling
- Reuse Rails business logic
- Version the internal API

**Cons:**
- Added latency
- Network dependency
- More moving parts

**RECOMMENDATION:** Start with **Option 1** (direct DB), move to **Option 3** later if needed.

---

## Implementation Roadmap

### Phase 1: Foundation (SFMCP-2) ✅ COMPLETE

- [x] Project structure
- [x] Gemfile with MCP SDK
- [x] GitHub repository
- [x] Documentation skeleton

### Phase 2: Database Integration (SFMCP-5)

**Tasks:**
1. Copy `database.yml` from SureFinance Rails app
2. Copy core models: `Account`, `Transaction`, `Family`, `Category`, `Budget`
3. Add family scoping to all queries
4. Test database connectivity

**Implementation:**

```ruby
# lib/surefinance_mcp/database.rb
module SurefinanceMCP
  class Database
    def self.build(logger:)
      config_path = File.join(__dir__, "../../config/database.yml")
      config = YAML.load(ERB.new(File.read(config_path)).result, aliases: true)

      env = ENV.fetch("MCP_SERVER_ENV", "development")
      ActiveRecord::Base.establish_connection(config[env])

      logger.info("Database connected: #{config[env]['database']}")

      # Load models
      require_relative "models"
    end
  end
end
```

**Models to copy (with adjustments):**
- `application_record.rb` - Base class
- `family.rb` - Multi-tenant root
- `account.rb` - Financial accounts
- `transaction.rb` - Transactions (via Entry)
- `entry.rb` - Polymorphic join
- `category.rb` - Categories
- `budget.rb` - Budgets
- `holding.rb` - Investment holdings
- `balance.rb` - Balance history

**Critical: Add family scoping helper:**

```ruby
# lib/surefinance_mcp/models/concerns/family_scoped.rb
module SurefinanceMCP
  module FamilyScoped
    extend ActiveSupport::Concern

    included do
      def self.for_family(family_id)
        family = Family.find(family_id)
        where(family_id: family_id)
      end
    end
  end
end
```

### Phase 3: Authentication (SFMCP-6)

**Requirements:**
- Family-scoped access only
- Support API keys + JWT
- Rate limiting per client

**Implementation:**

```ruby
# lib/surefinance_mcp/authentication/strategies/api_key.rb
class ApiKeyStrategy
  def authenticate(request)
    api_key = request.env['HTTP_AUTHORIZATION']&.sub(/^Bearer /, '')
    return nil unless api_key

    # Validate against environment or database
    if api_key == ENV['MCP_API_KEY']
      # Return family_id embedded in key or from config
      { family_id: ENV['DEFAULT_FAMILY_ID'].to_i }
    end
  end
end

# lib/surefinance_mcp/authentication/strategies/jwt.rb
class JwtStrategy
  def authenticate(request)
    token = request.env['HTTP_AUTHORIZATION']&.sub(/^Bearer /, '')
    return nil unless token

    payload = JWT.decode(token, ENV['JWT_SECRET'], true, algorithm: 'HS256')
    {
      family_id: payload[0]['family_id'],
      user_id: payload[0]['user_id']
    }
  rescue JWT::DecodeError
    nil
  end
end

# Composite
class Authenticator
  def initialize(strategies = [ApiKeyStrategy.new, JwtStrategy.new])
    @strategies = strategies
  end

  def authenticate(request)
    @strategies.each do |strategy|
      result = strategy.authenticate(request)
      return result if result
    end

    raise Unauthorized, "Authentication required"
  end
end
```

### Phase 4: Tool Implementation (SFMCP-3)

**Tools to implement:**

1. **get_accounts** - List accounts with balances
2. **get_account_balance_history** - Time series data
3. **get_transactions** - Query transactions with filters
4. **search_transactions** - Full-text search
5. **get_budgets** - Budget overview
6. **get_categories** - Category list

**Example: get_transactions**

```ruby
class GetTransactionsTool < MCP::Tool
  description "Query transactions with optional filters"

  input_schema(
    properties: {
      account_id: {
        type: "integer",
        description: "Filter by account ID"
      },
      category_id: {
        type: "integer",
        description: "Filter by category ID"
      },
      start_date: {
        type: "string",
        format: "date",
        description: "Start date (YYYY-MM-DD)"
      },
      end_date: {
        type: "string",
        format: "date",
        description: "End date (YYYY-MM-DD)"
      },
      kind: {
        type: "string",
        enum: ["standard", "funds_movement", "cc_payment", "loan_payment", "one_time"],
        description: "Transaction kind"
      },
      limit: {
        type: "integer",
        default: 100,
        minimum: 1,
        maximum: 1000
      }
    }
  )

  annotations(
    title: "Get Transactions",
    read_only_hint: true,
    idempotent_hint: true
  )

  class << self
    def call(
      account_id: nil,
      category_id: nil,
      start_date: nil,
      end_date: nil,
      kind: nil,
      limit: 100,
      server_context:
    )
      family = Family.find(server_context[:family_id])

      # Start with family transactions
      txns = family.transactions

      # Apply filters
      txns = txns.joins(:entry).where(entries: { account_id: account_id }) if account_id
      txns = txns.where(category_id: category_id) if category_id
      txns = txns.joins(:entry).where('entries.date >= ?', start_date) if start_date
      txns = txns.joins(:entry).where('entries.date <= ?', end_date) if end_date
      txns = txns.where(kind: kind) if kind

      # Order by date desc, limit
      txns = txns.joins(:entry).order('entries.date DESC').limit(limit)

      # Format response
      result = txns.map do |txn|
        {
          id: txn.id,
          date: txn.entry.date.iso8601,
          name: txn.entry.name,
          amount: txn.entry.amount.to_s,
          currency: txn.entry.currency,
          kind: txn.kind,
          category: txn.category&.name,
          merchant: txn.merchant&.name,
          account_id: txn.entry.account_id,
          tags: txn.tags.pluck(:name)
        }
      end

      MCP::Tool::Response.new([{
        type: "text",
        text: JSON.pretty_generate({
          count: result.length,
          transactions: result
        })
      }])
    rescue => e
      MCP::Tool::Response.new([{
        type: "text",
        text: JSON.generate({
          error: e.message,
          type: e.class.name
        })
      }], isError: true)
    end
  end
end
```

### Phase 5: Resource Implementation (SFMCP-4)

**Resources to implement:**

- `surefinance://accounts/{id}` - Account details
- `surefinance://transactions/{id}` - Transaction details
- `surefinance://budgets/{id}` - Budget details
- `surefinance://holdings/{id}` - Holding details

**Example: Account resource**

```ruby
server.resources_read_handler do |params|
  uri = params[:uri]
  family_id = params[:server_context][:family_id]

  case uri
  when %r{^surefinance://accounts/(\d+)$}
    account_id = $1.to_i
    account = Account.find_by(id: account_id, family_id: family_id)

    raise "Account not found" unless account

    [{
      uri: uri,
      mimeType: "application/json",
      text: JSON.pretty_generate({
        id: account.id,
        name: account.name,
        balance: account.balance.to_s,
        currency: account.currency,
        classification: account.classification,
        accountable_type: account.accountable_type,
        subtype: account.subtype,
        status: account.status,
        recent_transactions: account.transactions.limit(10).map { |t|
          {
            id: t.id,
            date: t.entry.date.iso8601,
            name: t.entry.name,
            amount: t.entry.amount.to_s
          }
        },
        balance_history: account.balances.order(date: :desc).limit(30).map { |b|
          {
            date: b.date.iso8601,
            balance: b.balance.to_s
          }
        }
      })
    }]
  else
    raise MCP::Error.new(code: -32602, message: "Unknown resource: #{uri}")
  end
end
```

### Phase 6: Docker Deployment (SFMCP-7)

```dockerfile
# Dockerfile
FROM ruby:3.4.4-alpine

WORKDIR /app

# Install dependencies
RUN apk add --no-cache \
    build-base \
    libpq-dev \
    tzdata

# Copy Gemfiles
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

# Copy app
COPY . .

# Run server
CMD ["bundle", "exec", "ruby", "lib/surefinance_mcp.rb"]
```

```yaml
# docker-compose.yml
version: "3.9"

services:
  surefinance-mcp:
    build: .
    ports:
      - "3500:3500"
    environment:
      MCP_SERVER_HOST: 0.0.0.0
      MCP_SERVER_PORT: 3500
      MCP_SERVER_ENV: production
      DATABASE_URL: postgresql://user:pass@surefinance-db:5432/surefinance_production
      API_KEY: ${MCP_API_KEY}
      JWT_SECRET: ${JWT_SECRET}
      LOG_LEVEL: info
    networks:
      - surefinance-network
    restart: unless-stopped

networks:
  surefinance-network:
    external: true  # Connect to SureFinance Rails network
```

---

## Authentication & Authorization

### Security Considerations

1. **Family Isolation** - CRITICAL
   - NEVER query across families
   - Always scope to `server_context[:family_id]`
   - Validate family_id exists

2. **Rate Limiting**
   ```ruby
   use Rack::Attack

   Rack::Attack.throttle("mcp/ip", limit: 300, period: 5.minutes) do |req|
     req.ip if req.path.start_with?("/")
   end

   Rack::Attack.throttle("mcp/family", limit: 1000, period: 1.hour) do |req|
     req.env['authenticated_family_id']
   end
   ```

3. **API Key Generation**
   ```ruby
   # Generate secure API keys
   api_key = SecureRandom.urlsafe_base64(32)

   # Store with family association
   # Format: mcp_<family_id>_<random>
   "mcp_#{family_id}_#{SecureRandom.hex(16)}"
   ```

4. **JWT Token Structure**
   ```ruby
   payload = {
     family_id: family.id,
     user_id: user.id,
     iat: Time.current.to_i,
     exp: (Time.current + 1.hour).to_i
   }

   JWT.encode(payload, ENV['JWT_SECRET'], 'HS256')
   ```

---

## Testing Strategy

### Unit Tests (RSpec)

```ruby
# spec/surefinance_mcp/tools/get_accounts_tool_spec.rb
RSpec.describe GetAccountsTool do
  let(:family) { create(:family) }
  let(:server_context) { { family_id: family.id } }

  before do
    create(:account, family: family, name: "Checking", balance: 1000)
    create(:account, family: family, name: "Savings", balance: 5000)
  end

  it "returns all family accounts" do
    response = described_class.call(server_context: server_context)

    json = JSON.parse(response.content.first[:text])
    expect(json["accounts"].count).to eq(2)
  end

  it "scopes to family" do
    other_family = create(:family)
    create(:account, family: other_family, name: "Other", balance: 999)

    response = described_class.call(server_context: server_context)
    json = JSON.parse(response.content.first[:text])

    expect(json["accounts"].count).to eq(2)
    expect(json["accounts"].map { |a| a["name"] }).not_to include("Other")
  end
end
```

### Integration Tests

```ruby
# spec/integration/mcp_server_spec.rb
RSpec.describe "MCP Server Integration" do
  let(:app) { build_mcp_app }

  it "handles tools/list request" do
    post "/", {
      jsonrpc: "2.0",
      method: "tools/list",
      id: 1
    }.to_json, {
      "CONTENT_TYPE" => "application/json",
      "HTTP_AUTHORIZATION" => "Bearer #{valid_api_key}"
    }

    expect(last_response.status).to eq(200)
    json = JSON.parse(last_response.body)
    expect(json["result"]["tools"].map { |t| t["name"] }).to include("get_accounts")
  end
end
```

### Test Fixtures

```ruby
# spec/support/fixtures.rb
FactoryBot.define do
  factory :family do
    name { "Test Family" }
    currency { "USD" }
  end

  factory :account do
    family
    name { "Test Account" }
    balance { 1000.0 }
    currency { "USD" }
    classification { "asset" }
    accountable_type { "Depository" }
  end
end
```

---

## Deployment

### Environment Variables

```bash
# .env.production
MCP_SERVER_HOST=0.0.0.0
MCP_SERVER_PORT=3500
MCP_SERVER_ENV=production

# Database
DATABASE_URL=postgresql://user:pass@host:5432/surefinance_production

# Authentication
MCP_API_KEY=mcp_1_abc123...
JWT_SECRET=super-secret-jwt-key

# Logging
LOG_LEVEL=info
LOG_FORMAT=json

# Optional: Error Reporting
BUGSNAG_API_KEY=...
```

### Health Check Endpoint

```ruby
server.define_custom_method(method_name: "health") do |params|
  {
    status: "healthy",
    database: ActiveRecord::Base.connection.active?,
    version: "1.0.0",
    timestamp: Time.current.iso8601
  }
end
```

### Monitoring

```ruby
MCP.configure do |config|
  config.instrumentation_callback = ->(data) {
    # Send to metrics service (StatsD, Datadog, etc.)
    StatsD.increment("mcp.#{data[:method]}")
    StatsD.timing("mcp.#{data[:method]}.duration", data[:duration])

    if data[:error]
      StatsD.increment("mcp.errors", tags: ["method:#{data[:method]}"])
    end
  }
end
```

---

## Quick Reference

### Common Patterns

**Family-scoped query:**
```ruby
family = Family.find(server_context[:family_id])
family.accounts.visible
```

**Error handling:**
```ruby
rescue ActiveRecord::RecordNotFound => e
  MCP::Tool::Response.new([{
    type: "text",
    text: JSON.generate({ error: "Not found" })
  }], isError: true)
```

**Money formatting:**
```ruby
account.balance.to_s  # "1000.00 USD"
account.balance.cents # 100000 (integer cents)
```

**Date filtering:**
```ruby
entries.where('date >= ?', start_date)
      .where('date <= ?', end_date)
```

### Debugging Tips

1. **Test database connection:**
   ```ruby
   ActiveRecord::Base.connection.execute("SELECT 1")
   ```

2. **Check family scoping:**
   ```ruby
   family = Family.find(1)
   family.accounts.count  # Should only see this family's accounts
   ```

3. **Inspect MCP requests:**
   ```ruby
   logger.debug("MCP Request: #{request.body.read}")
   ```

4. **Test tools in console:**
   ```ruby
   GetAccountsTool.call(server_context: { family_id: 1 })
   ```

---

## Additional Resources

- [MCP Ruby SDK Documentation](https://github.com/modelcontextprotocol/ruby-sdk)
- [MCP Specification](https://modelcontextprotocol.io/specification)
- [SureFinance Rails App](https://github.com/maybe-finance/maybe)
- [Project Issues](https://pm.oculair.ca/workbench/agentspace/browse/SFMCP)
- [BookStack Documentation](https://docs.oculair.ca/books/surefinance-mcp-server)

---

## Support

For questions or issues:
- GitHub Issues: https://github.com/oculairmedia/surefinance-mcp-server/issues
- Huly Project: https://pm.oculair.ca/workbench/agentspace/browse/SFMCP
