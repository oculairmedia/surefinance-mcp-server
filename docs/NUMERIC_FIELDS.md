# Numeric Field Handling

## Overview

The SureFinance MCP server uses FastMcp with dry-schema validation, which enforces **strict type checking** for numeric fields. All numeric values MUST be sent as floats, not integers.

## Why This Requirement Exists

FastMcp's dry-schema validation layer:
1. Infers `Float` type from JSON schema's `"type": "number"`
2. Validates arguments BEFORE tool code executes
3. Rejects `Integer` values with validation error: `{"field":["must be a float"]}`

This validation happens at the request parsing layer and cannot be intercepted without modifying the FastMcp gem itself.

## Client-Side Solution

**All MCP clients MUST convert integers to floats before sending requests.**

### Examples

❌ **Incorrect:**
```json
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "account_ops",
    "arguments": {
      "action": "create",
      "name": "Checking Account",
      "type": "Depository",
      "opening_balance": 100
    }
  }
}
```

✅ **Correct:**
```json
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "account_ops",
    "arguments": {
      "action": "create",
      "name": "Checking Account",
      "type": "Depository",
      "opening_balance": 100.0
    }
  }
}
```

## Affected Fields

All numeric fields across all tools require float values:

### account_ops
- `opening_balance` (create)
- `statement_balance` (reconcile)

### transaction_ops
- `amount` (create, update)

### transfer_ops
- `amount` (create)

### budget_ops
- `budgeted_spending` (create, update, assign_category)
- `expected_income` (create, update)

### asset_ops
- `quantity` (create_holding, update_holding)
- `price` (create_holding, update_holding)
- `amount` (create_holding, update_holding)

## Implementation Guidance

### JavaScript/TypeScript
```javascript
// Convert all numeric values to floats
const payload = {
  opening_balance: Number(100).toFixed(1)  // "100.0"
};

// Or use explicit float notation
const payload = {
  opening_balance: 100.0
};
```

### Python
```python
# Convert all numeric values to floats
payload = {
    "opening_balance": float(100)  # 100.0
}
```

### Ruby
```ruby
# Convert all numeric values to floats
payload = {
  opening_balance: 100.to_f  # 100.0
}
```

### Go
```go
// Use float64 for all numeric values
payload := map[string]interface{}{
    "opening_balance": float64(100),  // 100.0
}
```

## Server-Side Handling

Once values pass validation as floats, the server:
1. Accepts the float value
2. Uses `coerce_decimal` helper (in BaseTool) to convert to BigDecimal
3. Stores as decimal in PostgreSQL

This ensures:
- Precise decimal arithmetic (no floating-point errors)
- Proper currency/monetary value handling
- Database-level precision

## Troubleshooting

If you receive validation errors like:
```json
{
  "error": {
    "type": "validation_error",
    "code": "account_ops.invalid",
    "message": "Account validation failed",
    "fields": {
      "opening_balance": ["must be a float"]
    }
  }
}
```

**Solution:** Ensure ALL numeric values in your request are floats (e.g., `100.0` not `100`).

## Why Not Fix Server-Side?

We investigated multiple server-side approaches:
1. ❌ Patching FastMcp::Tool#call - validation happens before call
2. ❌ Patching FastMcp::Tool#initialize - still too late
3. ❌ Patching Dry::Schema - wrong validation layer
4. ❌ Rack middleware - FastMcp bypasses middleware for /mcp endpoint

All failed because FastMcp's validation happens in the request parsing layer, before any application code executes. Fixing this would require:
- Forking and modifying the fast-mcp gem
- Ongoing maintenance burden
- Risk of breaking changes

**Client-side coercion is the most practical, reliable solution.**
