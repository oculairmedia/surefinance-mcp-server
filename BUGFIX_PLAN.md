# SureFinance MCP Bug Fix Implementation Plan

**Generated:** 2025-10-14
**Status:** In Progress
**Priority:** High

## Executive Summary

This document outlines a comprehensive plan to address all bugs and inconsistencies found during MCP tool testing. Issues are organized into 5 phases prioritized by impact on user experience and system stability.

---

## Current Issues Overview

### Critical (Affects User Experience)
- ❌ Budget operations return "internal" errors for user validation issues
- ❌ Holdings create returns "internal" error
- ❌ Account create rejects integer `opening_balance`
- ❌ Numeric fields reject integers across multiple tools

### High (Consistency & Reliability)
- ⚠️  Delete responses vary: `deleted`, `destroyed`, `removed`
- ⚠️  Budget create behavior differs by month (Oct works, Nov fails)
- ⚠️  Idempotency not consistently enforced
- ⚠️  Error structures heterogeneous across tools

### Medium (Developer Experience)
- ⚠️  Unstable endpoints (holdings, recurring) still exposed
- ⚠️  Numeric rendering mixes decimals/exponential notation
- ⚠️  Category validation requires lucide_icon/color but not documented

### Low (Future Improvements)
- 📝 Missing contract tests for error paths
- 📝 Observability gaps (metrics, structured logging)
- 📝 Documentation incomplete for validation rules

---

## Phase 1: Critical Validation & Error Handling Fixes

**Goal:** Ensure all validation errors return proper 422 responses, not 500/internal

### 1.1 Create Standardized Error Response Structure

**Files to modify:**
- `lib/surefinance_mcp/tools/base_tool.rb`
- All handlers in `lib/surefinance_mcp/tools/handlers/`

**Implementation:**

```ruby
# lib/surefinance_mcp/tools/base_tool.rb
module SurefinanceMCP
  module Tools
    module BaseTool
      # Standardized error response
      def error_response(type:, code:, message:, fields: nil)
        {
          ok: false,
          error: {
            type: type,           # validation_error | not_found | internal | not_implemented
            code: code,           # tool.action_type (e.g., "budget.validation_error")
            message: message
          }.tap { |err| err[:fields] = fields if fields }
        }
      end

      def validation_error(message, fields = nil)
        error_response(
          type: "validation_error",
          code: "#{tool_name}.invalid",
          message: message,
          fields: fields
        )
      end

      def not_found_error(message)
        error_response(
          type: "not_found",
          code: "#{tool_name}.not_found",
          message: message
        )
      end

      def internal_error(message = "Internal error")
        error_response(
          type: "internal",
          code: "#{tool_name}.internal",
          message: message
        )
      end
    end
  end
end
```

### 1.2 Fix Budget Operations Error Handling

**File:** `lib/surefinance_mcp/tools/handlers/budget_ops.rb`

**Issues:**
- Nov budget returns "internal" instead of validation error
- No field-level error details

**Actions:**
1. Add proper validation for month/period format
2. Return validation_error with field details
3. Handle duplicate budget creation gracefully

```ruby
# Example fix in create_budget
def create_budget(payload)
  family_id = server_context[:family_id]

  # Validate month format
  if payload[:month]
    unless payload[:month] =~ /^[A-Z][a-z]{2}-\d{4}$/
      return validation_error(
        "Invalid month format",
        { month: ["must be in format 'Oct-2025'"] }
      )
    end
  end

  # Parse and validate dates
  start_date = parse_start_date(payload)
  return validation_error("Invalid date", { start_date: ["invalid date"] }) unless start_date

  # Check for existing budget
  existing = Models::Budget.find_by(family_id: family_id, period_start: start_date)
  if existing
    return { ok: true, result: { budget: serialize_budget(existing), existed: true } }
  end

  # Create new budget
  budget = Models::Budget.create!(
    family_id: family_id,
    period_start: start_date,
    expected_income: payload[:expected_income] || 0,
    budgeted_spending: payload[:budgeted_spending] || 0
  )

  { ok: true, result: { budget: serialize_budget(budget) } }
rescue ActiveRecord::RecordInvalid => e
  validation_error(
    "Budget validation failed",
    e.record.errors.messages
  )
end
```

### 1.3 Fix Holdings Create Error Handling

**File:** `lib/surefinance_mcp/tools/handlers/asset_ops.rb`

**Issues:**
- Returns "internal" error for validation failures
- No helpful field-level errors

**Actions:**
1. Add validation before create
2. Provide helpful error messages for required fields
3. Handle missing account gracefully

```ruby
def create_holding(payload)
  family_id = server_context[:family_id]

  # Validate required fields
  unless payload[:account_id]
    return validation_error(
      "Account ID required",
      { account_id: ["is required"] }
    )
  end

  # Find account with proper error handling
  account = Models::Account.find_for_family!(family_id, payload[:account_id])

  # Build holding
  holding = Models::Holding.new(account_id: account.id)
  assign_if_column(holding, :security_id, payload[:security_id])
  assign_if_column(holding, :qty, payload[:quantity])
  assign_if_column(holding, :currency, payload[:currency])
  assign_if_column(holding, :price, payload[:price])
  assign_if_column(holding, :amount, payload[:amount])
  assign_if_column(holding, :date, parse_date(payload[:date]) || Date.today)

  holding.save!
  { ok: true, result: { holding: serialize_holding(holding) } }
rescue ActiveRecord::RecordNotFound => e
  not_found_error("Account not found")
rescue ActiveRecord::RecordInvalid => e
  validation_error(
    "Holding validation failed",
    e.record.errors.messages
  )
end
```

### 1.4 Fix Account Operations Integer Rejection

**File:** `lib/surefinance_mcp/tools/handlers/account_ops.rb`

**Issue:** `opening_balance` rejects integers

**Action:** Already fixed with `.filled` but needs verification

**Test:**
```ruby
# Should accept all these:
opening_balance: 0
opening_balance: 100
opening_balance: 100.50
opening_balance: "100.50"
```

---

## Phase 2: Input Coercion & Schema Hardening

**Goal:** Accept integers, floats, and numeric strings; standardize serialization

### 2.1 Create Number Coercion Helper

**File:** `lib/surefinance_mcp/tools/base_tool.rb`

```ruby
module SurefinanceMCP
  module Tools
    module BaseTool
      # Coerce input to BigDecimal
      def coerce_decimal(value, field_name: nil)
        return nil if value.nil?
        BigDecimal(value.to_s)
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{field_name || 'Value'} must be a number"
      end

      # Serialize decimal to string (avoid exponential notation)
      def serialize_decimal(value)
        return nil if value.nil?
        value.to_s('F')
      end
    end
  end
end
```

### 2.2 Update All Numeric Fields to Use Coercion

**Files to update:**
- `budget_ops.rb`: expected_income, budgeted_spending
- `account_ops.rb`: opening_balance, statement_balance
- `transaction_ops.rb`: amount
- `asset_ops.rb`: quantity, price, amount
- `transfer_ops.rb`: amount

**Example:**
```ruby
# Before
amount = payload.fetch(:amount)

# After
amount = coerce_decimal(payload.fetch(:amount), field_name: 'amount')
```

### 2.3 Standardize All Numeric Serialization

**Action:** Update all serialize methods to use `serialize_decimal`

```ruby
def serialize_account(account)
  {
    id: account.id,
    name: account.name,
    balance: serialize_decimal(account[:balance]),
    current_balance: serialize_decimal(account[:current_balance]),
    # ...
  }.compact
end
```

### 2.4 Update Schema Definitions

**Goal:** All numeric fields should use `.filled` to accept any numeric type

**Files:** All handlers with numeric arguments

```ruby
# Pattern to find:
optional(:amount).value(:float)

# Replace with:
optional(:amount).filled.description("Amount (number or numeric string)")
```

---

## Phase 3: Idempotency & Atomicity

**Goal:** Consistent idempotency enforcement and atomic multi-record operations

### 3.1 Enforce Idempotency Keys on All Write Operations

**File:** `lib/surefinance_mcp/tools/idempotency.rb`

**Current state:** Idempotency wrapper exists but not consistently used

**Actions:**
1. Document idempotency key format
2. Add idempotency_key to all write operations
3. Return existing result if key already used

**Example:**
```ruby
# In each handler's call method:
def call(action:, idempotency_key: nil, **args)
  family_id = server_context[:family_id]
  tool_name = self.class.tool_name

  Tools::Idempotency.with_idempotency(
    tool: tool_name,
    key: idempotency_key.to_s,
    family_id: family_id
  ) do
    case action
    when "create" then create_resource(args)
    # ...
    end
  end
end
```

### 3.2 Add Budget Uniqueness Constraint

**Files:**
- Database migration (Rails app)
- `budget_ops.rb` create_budget method

**Database Migration:**
```ruby
# In surefinance-rails
class AddUniquenessConstraintToBudgets < ActiveRecord::Migration[8.0]
  def change
    add_index :budgets, [:family_id, :period_start], unique: true
  end
end
```

**Code Update:**
```ruby
def create_budget(payload)
  # Check for existing budget first
  existing = Models::Budget.find_by(
    family_id: family_id,
    period_start: start_date
  )

  if existing
    # Idempotent: return existing budget
    return { ok: true, result: { budget: serialize_budget(existing), existed: true } }
  end

  # Create new budget
  budget = Models::Budget.create!(...)
  { ok: true, result: { budget: serialize_budget(budget), created: true } }
end
```

### 3.3 Ensure Transfer Atomicity

**File:** `lib/surefinance_mcp/tools/handlers/transfer_ops.rb`

**Issue:** Transfer creates two entries; must be atomic

**Action:** Wrap in explicit transaction with proper rollback

```ruby
def create_transfer(payload)
  family_id = server_context[:family_id]

  from_account = Models::Account.find_for_family!(family_id, payload.fetch(:from_account_id))
  to_account = Models::Account.find_for_family!(family_id, payload.fetch(:to_account_id))
  amount = coerce_decimal(payload.fetch(:amount), field_name: 'amount')

  # Validate
  if from_account.id == to_account.id
    return validation_error("Cannot transfer to same account", { to_account_id: ["must differ from from_account_id"] })
  end

  transfer = nil

  ActiveRecord::Base.transaction do
    # Create outflow transaction
    outflow_txn = Models::Transaction.create!(...)
    outflow_entry = Models::Entry.create!(
      account_id: from_account.id,
      entryable: outflow_txn,
      amount: -amount.abs,
      # ...
    )

    # Create inflow transaction
    inflow_txn = Models::Transaction.create!(...)
    inflow_entry = Models::Entry.create!(
      account_id: to_account.id,
      entryable: inflow_txn,
      amount: amount.abs,
      # ...
    )

    # Create transfer record
    transfer = Models::Transfer.create!(
      inflow_transaction: inflow_txn,
      outflow_transaction: outflow_txn
    )
  end

  { ok: true, result: { transfer: serialize_transfer(transfer) } }
rescue ActiveRecord::RecordInvalid => e
  validation_error("Transfer validation failed", e.record.errors.messages)
rescue => e
  logger.error("Transfer failed: #{e.class} #{e.message}")
  internal_error("Transfer failed")
end
```

---

## Phase 4: Response Consistency & API Cleanup

**Goal:** Uniform response shapes and consistent behavior

### 4.1 Standardize Delete Responses

**Files:** All handlers with delete operations

**Current:** Mix of `deleted: true`, `destroyed: true`, `removed: true`

**Standard:**
```ruby
def delete_resource(payload)
  # ... delete logic ...

  {
    ok: true,
    result: {
      deleted: true,
      id: resource.id,
      resource_type: "budget"  # or "transaction", "category", etc.
    }
  }
end
```

### 4.2 Unify Success Response Format

**Standard response format:**
```ruby
{
  ok: true,
  result: {
    resource_name: { ...resource_data... },
    created: true,      # for create operations
    updated: true,      # for update operations
    deleted: true,      # for delete operations
    existed: true       # for idempotent creates that found existing
  }
}
```

### 4.3 Add Resource IDs to All Success Responses

**Action:** Ensure every successful response includes the resource ID

```ruby
# CREATE
{ ok: true, result: { budget: {..., id: "uuid"}, created: true } }

# UPDATE
{ ok: true, result: { budget: {..., id: "uuid"}, updated: true } }

# DELETE
{ ok: true, result: { deleted: true, id: "uuid", resource_type: "budget" } }
```

### 4.4 Include Metadata in Bulk Operations

**File:** `transaction_ops.rb` bulk_categorize

```ruby
def bulk_categorize(payload)
  # ... process transactions ...

  {
    ok: true,
    result: {
      results: results,
      summary: {
        total: results.size,
        success: success_count,
        failed: error_count
      }
    }
  }
end
```

### 4.5 Gate Unstable Endpoints

**Files:**
- `recurring_ops.rb` (already returns not_implemented)
- `asset_ops.rb` (holdings need gating)

**Option 1: Return not_implemented for holdings**
```ruby
def create_holding(payload)
  return {
    ok: false,
    error: {
      type: "not_implemented",
      code: "holdings.not_implemented",
      message: "Holdings feature is not yet stable"
    }
  }
end
```

**Option 2: Add stability flag to tool metadata**
```ruby
# In FastMcp::Tool subclass
def self.stability
  "experimental"  # or "stable", "deprecated"
end
```

---

## Phase 5: Testing & Observability

**Goal:** Comprehensive test coverage and production-ready monitoring

### 5.1 Add Contract Tests

**Files to create:**
- `spec/surefinance_mcp/tools/handlers/budget_ops_spec.rb`
- `spec/surefinance_mcp/tools/handlers/holdings_ops_spec.rb`
- `spec/surefinance_mcp/tools/handlers/transfer_ops_spec.rb`

**Test coverage:**
```ruby
# spec/surefinance_mcp/tools/handlers/budget_ops_spec.rb
RSpec.describe SurefinanceMCP::Tools::Handlers::BudgetOps do
  describe "#create_budget" do
    context "with valid data" do
      it "creates a new budget" do
        result = subject.call(action: "create", month: "Nov-2025", expected_income: 5000)
        expect(result[:ok]).to be true
        expect(result[:result][:budget][:id]).to be_present
      end

      it "accepts integer values" do
        result = subject.call(action: "create", month: "Dec-2025", expected_income: 5000)
        expect(result[:ok]).to be true
      end

      it "accepts float values" do
        result = subject.call(action: "create", month: "Jan-2026", expected_income: 5000.50)
        expect(result[:ok]).to be true
      end

      it "accepts string values" do
        result = subject.call(action: "create", month: "Feb-2026", expected_income: "5000.50")
        expect(result[:ok]).to be true
      end
    end

    context "with invalid data" do
      it "returns validation error for invalid month" do
        result = subject.call(action: "create", month: "Invalid")
        expect(result[:ok]).to be false
        expect(result[:error][:type]).to eq("validation_error")
        expect(result[:error][:fields][:month]).to be_present
      end

      it "returns validation error for non-numeric income" do
        result = subject.call(action: "create", month: "Mar-2026", expected_income: "abc")
        expect(result[:ok]).to be false
        expect(result[:error][:type]).to eq("validation_error")
      end
    end

    context "idempotency" do
      it "returns existing budget when created with same month" do
        result1 = subject.call(action: "create", month: "Apr-2026")
        result2 = subject.call(action: "create", month: "Apr-2026")

        expect(result2[:ok]).to be true
        expect(result2[:result][:existed]).to be true
        expect(result2[:result][:budget][:id]).to eq(result1[:result][:budget][:id])
      end
    end
  end
end
```

### 5.2 Add Structured Logging

**File:** `lib/surefinance_mcp/tools/audit_wrapper.rb`

**Enhancement:**
```ruby
module Tools
  module AuditWrapper
    def self.with_audit(tool:, action:, family_id:, params:)
      start_time = Time.now

      logger.info(
        event: "tool_call_start",
        tool: tool,
        action: action,
        family_id: family_id,
        idempotency_key: params[:idempotency_key]
      )

      result = yield

      duration_ms = ((Time.now - start_time) * 1000).round(2)

      logger.info(
        event: "tool_call_complete",
        tool: tool,
        action: action,
        family_id: family_id,
        duration_ms: duration_ms,
        success: result[:ok]
      )

      result
    rescue => e
      duration_ms = ((Time.now - start_time) * 1000).round(2)

      logger.error(
        event: "tool_call_error",
        tool: tool,
        action: action,
        family_id: family_id,
        duration_ms: duration_ms,
        error_class: e.class.name,
        error_message: e.message
      )

      raise
    end
  end
end
```

### 5.3 Add Metrics Instrumentation

**File:** `lib/surefinance_mcp/tools/metrics.rb` (new)

```ruby
module SurefinanceMCP
  module Tools
    module Metrics
      # Stub for metrics - implement with StatsD, Prometheus, etc.
      def self.increment(metric_name, tags = {})
        # Implementation depends on monitoring system
        logger.debug("METRIC: #{metric_name} #{tags.inspect}")
      end

      def self.timing(metric_name, duration_ms, tags = {})
        logger.debug("TIMING: #{metric_name} #{duration_ms}ms #{tags.inspect}")
      end
    end
  end
end
```

**Usage in AuditWrapper:**
```ruby
Metrics.increment("tool.call", tool: tool, action: action, status: "success")
Metrics.timing("tool.duration", duration_ms, tool: tool, action: action)
```

### 5.4 Add Error Path Tests

**Test categories:**
```ruby
describe "error handling" do
  it "returns validation_error for missing required fields"
  it "returns validation_error for invalid field types"
  it "returns validation_error for invalid field values"
  it "returns not_found for non-existent resources"
  it "returns internal for database errors"
  it "returns not_implemented for unstable features"
end
```

---

## Implementation Priority

### Week 1: Critical Fixes (Phase 1)
- [ ] Day 1-2: Standardize error response structure
- [ ] Day 3: Fix budget operations error handling
- [ ] Day 4: Fix holdings error handling
- [ ] Day 5: Verify account operations integer acceptance

### Week 2: Input Coercion (Phase 2)
- [ ] Day 1: Create number coercion helper
- [ ] Day 2-3: Update all handlers to use coercion
- [ ] Day 4: Standardize numeric serialization
- [ ] Day 5: Update schema definitions

### Week 3: Idempotency & Atomicity (Phase 3)
- [ ] Day 1-2: Enforce idempotency keys
- [ ] Day 3: Add budget uniqueness constraint
- [ ] Day 4-5: Ensure transfer atomicity

### Week 4: Response Consistency (Phase 4)
- [ ] Day 1: Standardize delete responses
- [ ] Day 2: Unify success response format
- [ ] Day 3: Add resource IDs to responses
- [ ] Day 4: Include metadata in bulk operations
- [ ] Day 5: Gate unstable endpoints

### Week 5: Testing & Observability (Phase 5)
- [ ] Day 1-3: Add contract tests
- [ ] Day 4: Add structured logging
- [ ] Day 5: Add metrics instrumentation

---

## Verification Checklist

After each phase, verify:

### Phase 1 Verification
- [ ] Budget create with Nov-2025 returns proper validation error (not internal)
- [ ] Holdings create with invalid data returns validation error with fields
- [ ] Account create accepts integer opening_balance (0, 100, etc.)
- [ ] All validation errors return type: "validation_error"
- [ ] All validation errors include error.fields when applicable

### Phase 2 Verification
- [ ] All numeric fields accept integers: `amount: 100`
- [ ] All numeric fields accept floats: `amount: 100.50`
- [ ] All numeric fields accept numeric strings: `amount: "100.50"`
- [ ] All numeric fields reject non-numeric strings: `amount: "abc"` → validation_error
- [ ] All numeric responses use decimal notation: `"100.50"` not `1.005e2`

### Phase 3 Verification
- [ ] Creating same budget twice with same idempotency_key returns same result
- [ ] Creating same budget twice without key returns existing budget
- [ ] Transfer failure rolls back both entries
- [ ] Transfer success creates both entries atomically
- [ ] Idempotency_key prevents duplicate writes across all tools

### Phase 4 Verification
- [ ] All delete operations return `{deleted: true, id: "..."}`
- [ ] All create operations include resource ID in response
- [ ] All update operations include resource ID in response
- [ ] Bulk operations include summary counts
- [ ] Holdings operations return not_implemented
- [ ] Recurring operations return not_implemented

### Phase 5 Verification
- [ ] Contract tests pass for all tools
- [ ] Error path tests cover validation, not_found, internal
- [ ] Structured logs include tool, action, duration, outcome
- [ ] Metrics emitted for success/error counts
- [ ] Documentation updated with validation rules

---

## Known Limitations & Future Work

### Limitations to Document
1. **Recurring transactions**: Not yet implemented (returns not_implemented)
2. **Holdings**: Unstable/experimental (should be gated)
3. **Split transactions**: Implementation incomplete (transfer_id lookup may not work)
4. **Category validation**: Requires lucide_icon and color for root categories

### Future Enhancements
1. **Batch operations**: Add batch create for transactions, categories
2. **Soft deletes**: Consider soft delete with archived flag
3. **Audit trail**: Enhanced audit logging with user attribution
4. **Webhooks**: Notify external systems of state changes
5. **Rate limiting**: Per-family rate limits on write operations

---

## Success Criteria

This plan is successful when:

1. ✅ All test matrix scenarios pass
2. ✅ Zero "internal" errors for user validation issues
3. ✅ All numeric fields accept int/float/string uniformly
4. ✅ Idempotency works consistently across all write operations
5. ✅ Response shapes are uniform and documented
6. ✅ Contract tests achieve >90% coverage
7. ✅ Observability allows debugging production issues
8. ✅ Documentation accurately reflects behavior

---

## Communication Plan

### Status Updates
- Daily: Update BUGFIX_PLAN.md with completed items
- Weekly: Summary report to stakeholders
- Ad-hoc: Communicate blockers immediately

### Documentation Updates
- Update `docs/mcp_tools_audit.md` with fixes
- Update `README.md` with validation rules
- Create `docs/tool_contracts.md` with request/response shapes

---

## Appendix: File Reference

### Files to Modify (Phase 1)
```
lib/surefinance_mcp/tools/base_tool.rb           NEW: Error response helpers
lib/surefinance_mcp/tools/handlers/budget_ops.rb  FIX: Error handling
lib/surefinance_mcp/tools/handlers/asset_ops.rb   FIX: Holdings errors
lib/surefinance_mcp/tools/handlers/account_ops.rb VERIFY: Integer acceptance
```

### Files to Modify (Phase 2)
```
lib/surefinance_mcp/tools/base_tool.rb            ADD: Coercion helpers
lib/surefinance_mcp/tools/handlers/*_ops.rb       UPDATE: Use coercion
```

### Files to Modify (Phase 3)
```
lib/surefinance_mcp/tools/idempotency.rb          ENHANCE: Documentation
lib/surefinance_mcp/tools/handlers/budget_ops.rb  ADD: Uniqueness check
lib/surefinance_mcp/tools/handlers/transfer_ops.rb FIX: Atomicity
```

### Files to Modify (Phase 4)
```
lib/surefinance_mcp/tools/handlers/*_ops.rb       STANDARDIZE: Responses
```

### Files to Create (Phase 5)
```
spec/surefinance_mcp/tools/handlers/*_spec.rb     NEW: Contract tests
lib/surefinance_mcp/tools/metrics.rb              NEW: Metrics
docs/tool_contracts.md                            NEW: API documentation
```

---

**Next Steps:** Begin Phase 1, starting with standardized error response structure in `base_tool.rb`.
