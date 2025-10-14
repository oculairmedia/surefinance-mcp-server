# Quick Start: Critical Bug Fixes

**Priority:** IMMEDIATE
**Estimated Time:** 2-3 days for critical fixes

## Top 5 Critical Issues

### 1. Budget Operations Return "Internal" Error
**File:** `lib/surefinance_mcp/tools/handlers/budget_ops.rb`
**Problem:** Nov-2025 budget creation fails with internal error instead of validation error
**Impact:** Users can't debug their requests

**Quick Fix:**
```ruby
def create_budget(payload)
  # Add validation before processing
  if payload[:month] && payload[:month] !~ /^[A-Z][a-z]{2}-\d{4}$/
    return {
      ok: false,
      error: {
        type: "validation_error",
        code: "budget.invalid",
        message: "Invalid month format",
        fields: { month: ["must be in format 'Oct-2025'"] }
      }
    }
  end

  # ... rest of implementation
end
```

---

### 2. Holdings Create Returns "Internal" Error
**File:** `lib/surefinance_mcp/tools/handlers/asset_ops.rb`
**Problem:** Validation errors return as internal errors
**Impact:** Cannot create holdings successfully

**Quick Fix:**
```ruby
def create_holding(payload)
  # ... existing code ...
rescue ActiveRecord::RecordInvalid => e
  {
    ok: false,
    error: {
      type: "validation_error",
      code: "holdings.invalid",
      message: "Holding validation failed",
      fields: e.record.errors.messages
    }
  }
end
```

---

### 3. Integer Rejection for Numeric Fields
**Files:** Multiple handlers
**Problem:** Fields like `opening_balance`, `quantity`, `price` reject integer values
**Impact:** Users must provide decimals even for whole numbers

**Quick Fix:**
```ruby
# In base_tool.rb
def coerce_decimal(value, field_name: nil)
  return nil if value.nil?
  BigDecimal(value.to_s)
rescue ArgumentError, TypeError
  raise ArgumentError, "#{field_name || 'Value'} must be a number"
end

# In handlers, replace:
amount = payload.fetch(:amount)
# With:
amount = coerce_decimal(payload.fetch(:amount), field_name: 'amount')
```

---

### 4. Inconsistent Delete Responses
**Files:** All delete operations
**Problem:** Returns mix of `deleted`, `destroyed`, `removed`
**Impact:** Client code must handle multiple response formats

**Quick Fix:**
```ruby
# Standardize all delete responses:
{
  ok: true,
  result: {
    deleted: true,
    id: resource.id
  }
}
```

---

### 5. No Idempotency for Budget Creation
**File:** `lib/surefinance_mcp/tools/handlers/budget_ops.rb`
**Problem:** Creating same budget twice may cause errors
**Impact:** Retries fail instead of being idempotent

**Quick Fix:**
```ruby
def create_budget(payload)
  # Check for existing first
  existing = Models::Budget.find_by(
    family_id: family_id,
    period_start: start_date
  )

  if existing
    return {
      ok: true,
      result: {
        budget: serialize_budget(existing),
        existed: true
      }
    }
  end

  # Create new budget
  # ...
end
```

---

## Immediate Action Items

### Day 1: Error Response Standardization
1. Create error helper methods in `base_tool.rb`:
   - `validation_error(message, fields = nil)`
   - `not_found_error(message)`
   - `internal_error(message = "Internal error")`

2. Update all handlers to use these helpers
3. Test: Verify budget Nov-2025 returns validation_error, not internal

### Day 2: Numeric Input Coercion
1. Add `coerce_decimal` helper to `base_tool.rb`
2. Update handlers to coerce numeric inputs:
   - `budget_ops.rb`: expected_income, budgeted_spending
   - `account_ops.rb`: opening_balance, statement_balance
   - `transaction_ops.rb`: amount
   - `asset_ops.rb`: quantity, price, amount
   - `transfer_ops.rb`: amount

3. Test: Verify integers, floats, strings all accepted

### Day 3: Response Consistency
1. Standardize delete responses across all handlers
2. Ensure all responses include resource IDs
3. Add idempotency check to budget create
4. Test: Verify consistent response shapes

---

## Testing Quick Commands

### Test Budget Nov-2025
```bash
curl -s -X POST http://localhost:4332/mcp -H "Content-Type: application/json" -d '{
  "jsonrpc":"2.0",
  "method":"tools/call",
  "params":{
    "name":"budget_ops",
    "arguments":{
      "action":"create",
      "month":"Nov-2025",
      "expected_income":5000
    }
  },
  "id":1
}' | jq '.result.content[0].text'
```

### Test Account Integer Balance
```bash
curl -s -X POST http://localhost:4332/mcp -H "Content-Type: application/json" -d '{
  "jsonrpc":"2.0",
  "method":"tools/call",
  "params":{
    "name":"account_ops",
    "arguments":{
      "action":"create",
      "name":"Test Account",
      "type":"Depository",
      "opening_balance":100
    }
  },
  "id":1
}' | jq '.result.content[0].text'
```

### Test Holdings Create
```bash
curl -s -X POST http://localhost:4332/mcp -H "Content-Type: application/json" -d '{
  "jsonrpc":"2.0",
  "method":"tools/call",
  "params":{
    "name":"asset_ops",
    "arguments":{
      "action":"create_holding",
      "account_id":"<ACCOUNT_ID>",
      "quantity":100,
      "price":50,
      "amount":5000
    }
  },
  "id":1
}' | jq '.result.content[0].text'
```

---

## Success Criteria (3-Day Sprint)

After 3 days, these should all pass:

- [ ] Budget create with "Nov-2025" returns validation_error (not internal)
- [ ] Budget create with invalid month includes error.fields.month
- [ ] Holdings create with validation error returns validation_error (not internal)
- [ ] Account create accepts `opening_balance: 100` (integer)
- [ ] Account create accepts `opening_balance: 100.50` (float)
- [ ] Account create accepts `opening_balance: "100.50"` (string)
- [ ] Transaction amount accepts all numeric types
- [ ] All delete operations return `{deleted: true, id: "..."}`
- [ ] Budget create twice with same month returns existing budget
- [ ] Transfer operations are atomic (both entries or neither)

---

## Rollout Plan

1. **Commit 1:** Error standardization helpers
2. **Commit 2:** Fix budget_ops error handling
3. **Commit 3:** Fix asset_ops error handling
4. **Commit 4:** Add numeric coercion helpers
5. **Commit 5:** Update all handlers to use coercion
6. **Commit 6:** Standardize delete responses
7. **Commit 7:** Add budget idempotency

Each commit should:
- Include tests
- Update relevant documentation
- Be independently deployable

---

## Risk Assessment

### Low Risk
- Error response standardization (additive)
- Numeric coercion (backward compatible)
- Response consistency (client should handle both)

### Medium Risk
- Budget idempotency (changes create behavior)
- Transfer atomicity (may expose edge cases)

### High Risk
- None identified

---

## Post-Implementation Verification

Run full test suite:
```bash
cd /opt/stacks/surefinance-mcp-server
docker-compose exec surefinance-mcp bundle exec rspec
```

Manual verification:
1. Create budget for Nov-2025 ✅
2. Create account with integer balance ✅
3. Create holding with numeric values ✅
4. Delete transaction, verify response shape ✅
5. Create same budget twice ✅

---

**Next:** Start with error standardization in `base_tool.rb`
