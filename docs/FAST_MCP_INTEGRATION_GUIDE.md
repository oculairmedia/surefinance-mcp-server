# Fast MCP Integration Guide for SureFinance

## Overview

[Fast MCP](https://github.com/yjacquin/fast-mcp) is an alternative Ruby MCP implementation that offers:

- **Simpler API**: More Ruby-idiomatic than the official SDK
- **Dry-Schema Validation**: Built-in argument validation using Dry-Schema
- **Rails Integration**: First-class Rails support with generators
- **Multiple Transports**: STDIO, HTTP, and SSE support
- **Dynamic Filtering**: Control tool/resource access based on context
- **Resource Templates**: URI template support for dynamic resources

## Key Differences from Official MCP SDK

| Feature | Official SDK (`mcp` gem) | Fast MCP (`fast-mcp` gem) |
|---------|-------------------------|---------------------------|
| **API Style** | Block-based or class-based | Class inheritance (Rails-style) |
| **Validation** | Manual JSON Schema | Dry-Schema DSL |
| **Rails Support** | Manual setup | Generator + auto-discovery |
| **Transport** | STDIO, HTTP | STDIO, HTTP, SSE |
| **Resource Templates** | Manual URI parsing | Built-in URI templates |
| **Authentication** | Manual | Built-in middleware |

## Installation

Add to your `Gemfile`:

```ruby
gem 'fast-mcp', git: 'https://github.com/yjacquin/fast-mcp.git'
```

Then run:

```bash
bundle install
```

## Core Concepts

### 1. Server Creation

```ruby
require 'fast_mcp'

server = FastMcp::Server.new(
  name: 'surefinance',
  version: '1.0.0'
)
```

### 2. Tool Definition

Tools inherit from `FastMcp::Tool`:

```ruby
class GetAccountsTool < FastMcp::Tool
  description "List all accounts with current balances"
  
  # Dry-Schema validation
  arguments do
    optional(:status).filled(:string)
      .value(included_in?: ['active', 'draft', 'disabled'])
      .description("Filter by account status")
    optional(:classification).filled(:string)
      .value(included_in?: ['asset', 'liability'])
      .description("Filter by classification")
  end
  
  def call(status: nil, classification: nil)
    # Access server context via @server_context
    family = Family.find(@server_context[:family_id])
    accounts = family.accounts.visible
    
    accounts = accounts.where(status: status) if status
    accounts = accounts.where(classification: classification) if classification
    
    # Return can be Hash, Array, or String
    accounts.map { |a| format_account(a) }
  end
  
  private
  
  def format_account(account)
    {
      id: account.id,
      name: account.name,
      balance: account.balance.to_s,
      currency: account.currency,
      classification: account.classification
    }
  end
end
```

### 3. Resource Definition

Resources inherit from `FastMcp::Resource`:

```ruby
class AccountResource < FastMcp::Resource
  uri "surefinance://accounts/{id}"
  resource_name "Account"
  description "Account details with balance history"
  mime_type "application/json"
  
  def content
    # params[:id] automatically parsed from URI template
    account_id = params[:id]
    family_id = @server_context[:family_id]
    
    account = Account.find_by(id: account_id, family_id: family_id)
    return nil unless account
    
    JSON.generate({
      id: account.id,
      name: account.name,
      balance: account.balance.to_s,
      balances: account.balances.limit(30).as_json
    })
  end
end
```

### 4. Server Registration

```ruby
# Register tools
server.register_tools(
  GetAccountsTool,
  GetTransactionsTool,
  GetBudgetsTool
)

# Register resources
server.register_resources(
  AccountResource,
  TransactionResource,
  BudgetResource
)

# Start server
server.start  # Uses STDIO transport by default
```

## Transport Options

### 1. STDIO Transport (Default)

```ruby
#!/usr/bin/env ruby
require 'fast_mcp'

server = FastMcp::Server.new(name: 'surefinance', version: '1.0.0')
server.register_tools(GetAccountsTool)
server.start  # STDIO transport
```

### 2. HTTP/SSE Transport (Rack Middleware)

```ruby
require 'fast_mcp'
require 'rack'

app = lambda { |env| [200, {}, ['OK']] }

mcp_app = FastMcp.rack_middleware(
  app,
  name: 'surefinance',
  version: '1.0.0',
  path_prefix: '/mcp',
  messages_route: 'messages',
  sse_route: 'sse'
) do |server|
  server.register_tools(GetAccountsTool)
  server.register_resources(AccountResource)
end

run mcp_app
```

### 3. Authenticated HTTP Transport

```ruby
mcp_app = FastMcp.authenticated_rack_middleware(
  app,
  name: 'surefinance',
  version: '1.0.0',
  auth_token: ENV['MCP_AUTH_TOKEN'],
  allowed_origins: ['localhost', '127.0.0.1']
) do |server|
  server.register_tools(GetAccountsTool)
end
```

## Migration from Official SDK

### Current SureFinance Implementation

Our current implementation uses the official SDK:

```ruby
# lib/surefinance_mcp/tools/handlers/get_accounts.rb
class GetAccountsTool < MCP::Tool
  description "List all accounts"
  
  input_schema(
    properties: {
      status: {
        type: "string",
        enum: ["active", "draft", "disabled"]
      }
    }
  )
  
  class << self
    def call(status: nil, server_context:)
      # Implementation
    end
  end
end
```

### Fast MCP Equivalent

```ruby
class GetAccountsTool < FastMcp::Tool
  description "List all accounts"
  
  arguments do
    optional(:status).filled(:string)
      .value(included_in?: ['active', 'draft', 'disabled'])
  end
  
  def call(status: nil)
    # Access context via @server_context instead of parameter
    family_id = @server_context[:family_id]
    # Implementation
  end
end
```

### Key Migration Changes

1. **Class inheritance**: Change from `< MCP::Tool` to `< FastMcp::Tool`
2. **Arguments DSL**: Replace `input_schema` with `arguments do ... end`
3. **Context access**: Use `@server_context` instance variable instead of `server_context:` parameter
4. **Server setup**: Use `FastMcp::Server` instead of `MCP::Server`

## Advanced Features

### 1. Dynamic Tool Filtering

Control which tools are available based on request context:

```ruby
server.filter_tools do |request, tools|
  family_id = request.server_context[:family_id]
  user_role = request.params['role']
  
  case user_role
  when 'admin'
    tools  # All tools
  when 'user'
    tools.reject { |t| t.tags.include?(:admin) }
  else
    tools.select { |t| t.tags.include?(:public) }
  end
end
```

### 2. Tool Tags

```ruby
class DeleteAccountTool < FastMcp::Tool
  tags :admin, :dangerous
  description "Delete an account"
  
  def call(account_id:)
    # Implementation
  end
end
```

### 3. Resource Notifications

Notify clients when resources update:

```ruby
class UpdateAccountTool < FastMcp::Tool
  def call(account_id:, balance:)
    account = Account.find(account_id)
    account.update!(balance: balance)
    
    # Notify clients the resource changed
    notify_resource_updated("surefinance://accounts/#{account_id}")
    
    { success: true }
  end
end
```

### 4. Complex Validation

```ruby
class CreateTransactionTool < FastMcp::Tool
  arguments do
    required(:amount).filled(:decimal).description("Transaction amount")
    required(:date).filled(:date).description("Transaction date")
    required(:account_id).filled(:integer).description("Account ID")
    
    optional(:metadata).hash do
      optional(:merchant).filled(:string)
      optional(:category).filled(:string)
      optional(:tags).array(:string)
    end
  end
  
  def call(amount:, date:, account_id:, metadata: {})
    # Implementation with validated arguments
  end
end
```

## Rack Middleware Integration

For standalone HTTP server:

```ruby
# config.ru
require 'fast_mcp'
require_relative 'lib/surefinance_mcp'

app = lambda { |env| [200, {}, ['SureFinance MCP']] }

mcp_app = FastMcp.authenticated_rack_middleware(
  app,
  name: 'surefinance',
  version: '1.0.0',
  auth_token: ENV['MCP_AUTH_TOKEN'],
  path_prefix: '/mcp'
) do |server|
  # Load all tool classes
  Dir[File.join(__dir__, 'lib/surefinance_mcp/tools/handlers/**/*.rb')].each do |file|
    require file
  end
  
  # Register tools
  server.register_tools(
    GetAccountsTool,
    GetTransactionsTool,
    SearchTransactionsTool,
    GetBudgetsTool,
    GetCategoriessTool,
    GetAccountBalanceHistoryTool
  )
  
  # Load all resource classes
  Dir[File.join(__dir__, 'lib/surefinance_mcp/resources/handlers/**/*.rb')].each do |file|
    require file
  end
  
  # Register resources
  server.register_resources(
    AccountResource,
    TransactionResource,
    BudgetResource,
    HoldingResource
  )
end

run mcp_app
```

Run with:

```bash
bundle exec rackup -p 3500
```

## Testing with MCP Inspector

```bash
# Test STDIO transport
npx @modelcontextprotocol/inspector lib/surefinance_mcp.rb

# Test HTTP/SSE transport
# Start your server first, then:
npx @modelcontextprotocol/inspector
# In the UI, select "SSE" and enter: http://localhost:3500/mcp/sse
```

## Configuration for Claude Desktop

```json
{
  "mcpServers": {
    "surefinance": {
      "command": "ruby",
      "args": ["u:/surefinance-mcp-server/lib/surefinance_mcp.rb"],
      "env": {
        "DATABASE_URL": "postgresql://user:pass@localhost/surefinance",
        "API_KEY": "your-api-key"
      }
    }
  }
}
```

## Pros and Cons

### Pros of Fast MCP

✅ **Simpler API**: More Ruby-idiomatic  
✅ **Better Validation**: Dry-Schema is more expressive than JSON Schema  
✅ **Rails Integration**: Generators and auto-discovery  
✅ **Resource Templates**: Built-in URI template support  
✅ **Active Development**: Frequent updates and improvements  
✅ **Better Documentation**: More examples and guides  

### Cons of Fast MCP

❌ **Less Mature**: Newer than official SDK  
❌ **Different API**: Migration requires refactoring  
❌ **Community**: Smaller community than official SDK  
❌ **Dependencies**: Adds dry-schema dependency  

## Recommendation

**Current Status**: Stick with official SDK for now

**Reasons**:
1. ✅ Already implemented and working
2. ✅ Official SDK is stable and well-supported
3. ✅ No urgent need to migrate
4. ✅ Official SDK meets all current requirements

**Future Consideration**: Consider Fast MCP if:
- You need more complex validation logic
- You want Rails-style generators
- You need SSE transport support
- You want dynamic tool filtering
- Official SDK becomes unmaintained

## Example: Full Tool Migration

### Before (Official SDK)

```ruby
# lib/surefinance_mcp/tools/handlers/get_transactions.rb
class GetTransactionsTool < MCP::Tool
  description "Query transactions with filters"
  
  input_schema(
    properties: {
      account_id: { type: "integer" },
      start_date: { type: "string", format: "date" },
      end_date: { type: "string", format: "date" },
      limit: { type: "integer", default: 100 }
    }
  )
  
  class << self
    def call(account_id: nil, start_date: nil, end_date: nil, limit: 100, server_context:)
      family = Family.find(server_context[:family_id])
      transactions = family.transactions
      
      transactions = transactions.where(account_id: account_id) if account_id
      transactions = transactions.where('date >= ?', start_date) if start_date
      transactions = transactions.where('date <= ?', end_date) if end_date
      transactions = transactions.limit(limit)
      
      MCP::Tool::Response.new([{
        type: "text",
        text: transactions.to_json
      }])
    end
  end
end
```

### After (Fast MCP)

```ruby
# lib/surefinance_mcp/tools/handlers/get_transactions.rb
class GetTransactionsTool < FastMcp::Tool
  description "Query transactions with filters"
  
  arguments do
    optional(:account_id).filled(:integer)
      .description("Filter by account ID")
    optional(:start_date).filled(:date)
      .description("Start date for transactions")
    optional(:end_date).filled(:date)
      .description("End date for transactions")
    optional(:limit).filled(:integer)
      .description("Maximum number of transactions")
      .default(100)
  end
  
  def call(account_id: nil, start_date: nil, end_date: nil, limit: 100)
    family = Family.find(@server_context[:family_id])
    transactions = family.transactions
    
    transactions = transactions.where(account_id: account_id) if account_id
    transactions = transactions.where('date >= ?', start_date) if start_date
    transactions = transactions.where('date <= ?', end_date) if end_date
    transactions = transactions.limit(limit)
    
    # Can return Hash, Array, or String directly
    transactions.as_json
  end
end
```

## Resources

- **GitHub**: https://github.com/yjacquin/fast-mcp
- **Examples**: https://github.com/yjacquin/fast-mcp/tree/main/examples
- **Documentation**: https://github.com/yjacquin/fast-mcp/tree/main/docs
- **Discord**: https://discord.gg/9HHfAtY3HF

## Conclusion

Fast MCP is a compelling alternative to the official SDK, especially for Rails applications. However, for SureFinance, the official SDK is sufficient and already implemented. Consider Fast MCP for future projects or if specific features (like SSE transport or dynamic filtering) become requirements.