# SureFinance MCP Server - Feature Expansion Plan

**Goal**: Expand from read-only operations to full CRUD capabilities across all platform features

**Current State**: 6 read-only tools (show_accounts, list_transactions, find_transactions, show_balance_history, show_budgets, list_categories)

---

## Database Models Available

1. **Account** - Financial accounts (checking, savings, credit cards, etc.)
2. **AccountBalanceHistory** - Historical balance snapshots
3. **Budget** - Budget definitions with date ranges
4. **BudgetCategory** - Join table linking budgets to categories
5. **Category** - Hierarchical expense/income categories (parent/child relationships)
6. **Entry** - Double-entry ledger entries
7. **Family** - Top-level organization/workspace
8. **Holding** - Investment holdings (stocks, bonds, etc.)
9. **Transaction** - Financial transactions

---

## Phase 1: Category Management (Priority: HIGH)
**Duration**: 2-3 days

### Tools to Implement:
1. **create_category** - Create new expense/income category
   - Parameters: name, type (expense/income), parent_id (optional), color, icon
   - Validation: unique name within family, valid parent hierarchy

2. **update_category** - Update category properties
   - Parameters: category_id, name, color, icon
   - Validation: cannot change parent (use move_category), name uniqueness

3. **move_category** - Move category in hierarchy
   - Parameters: category_id, new_parent_id (null for root level)
   - Validation: prevent circular references, maintain hierarchy integrity

4. **delete_category** - Delete category
   - Parameters: category_id, reassign_to_id (optional)
   - Logic: Reassign transactions to another category or orphan them
   - Validation: warn if category has transactions or children

5. **merge_categories** - Combine two categories
   - Parameters: source_id, target_id
   - Logic: Move all transactions and children to target, delete source

### Database Changes:
- None required (models already support full CRUD)

### Testing Requirements:
- Unit tests for each operation
- Integration tests for hierarchy operations
- Edge cases: circular references, orphaned transactions, concurrent updates

---

## Phase 2: Budget Management (Priority: HIGH)
**Duration**: 2-3 days

### Tools to Implement:
1. **create_budget** - Create new budget
   - Parameters: name, start_date, end_date, total_amount
   - Validation: date range validity, no overlapping budgets

2. **update_budget** - Update budget properties
   - Parameters: budget_id, name, start_date, end_date, total_amount
   - Validation: cannot change dates if budget is active

3. **delete_budget** - Delete budget
   - Parameters: budget_id
   - Logic: Cascade delete budget_categories associations

4. **assign_category_to_budget** - Link category to budget with amount
   - Parameters: budget_id, category_id, allocated_amount
   - Validation: allocated amounts don't exceed total budget

5. **remove_category_from_budget** - Unlink category from budget
   - Parameters: budget_id, category_id

6. **get_budget_progress** - Calculate budget vs actual spending
   - Parameters: budget_id
   - Returns: per-category spending vs allocation, total progress

### Database Changes:
- None required (budget_categories table already exists)

### Testing Requirements:
- Budget allocation validation
- Spending calculations accuracy
- Multi-category budget scenarios

---

## Phase 3: Transaction Management (Priority: MEDIUM)
**Duration**: 3-4 days

### Tools to Implement:
1. **create_transaction** - Create new transaction
   - Parameters: account_id, date, amount, description, category_id, tags
   - Logic: Create transaction + double-entry ledger entries
   - Validation: account exists, amount format, category exists

2. **update_transaction** - Update transaction details
   - Parameters: transaction_id, date, amount, description, category_id, tags
   - Logic: Update transaction + rebalance entries
   - Validation: cannot change account after creation

3. **delete_transaction** - Delete transaction
   - Parameters: transaction_id
   - Logic: Remove transaction + associated entries
   - Validation: confirm if deleting posted/reconciled transaction

4. **split_transaction** - Split transaction across multiple categories
   - Parameters: transaction_id, splits [{category_id, amount, description}]
   - Logic: Create child transactions for each split
   - Validation: split amounts sum to original amount

5. **categorize_transaction** - Assign/change category
   - Parameters: transaction_id, category_id
   - Logic: Update transaction category, optionally create rule

6. **bulk_categorize** - Apply category to multiple transactions
   - Parameters: transaction_ids[], category_id
   - Logic: Update multiple transactions efficiently

### Database Changes:
- May need `transaction_splits` table if not existing
- Add `reconciled` and `posted` flags if missing

### Testing Requirements:
- Double-entry integrity tests
- Account balance recalculation after updates/deletes
- Split transaction edge cases

---

## Phase 4: Account Management (Priority: MEDIUM)
**Duration**: 2-3 days

### Tools to Implement:
1. **create_account** - Create new account
   - Parameters: name, type (checking/savings/credit/investment), currency, initial_balance
   - Logic: Create account + opening balance entry
   - Validation: unique name within family

2. **update_account** - Update account properties
   - Parameters: account_id, name, currency, account_number
   - Validation: cannot change type or initial balance

3. **close_account** - Mark account as closed
   - Parameters: account_id, closing_date, transfer_to_account_id
   - Logic: Create closing entry, transfer remaining balance
   - Validation: confirm if balance not zero

4. **reopen_account** - Reactivate closed account
   - Parameters: account_id
   - Logic: Remove closed status, restore access

5. **reconcile_account** - Mark transactions as reconciled
   - Parameters: account_id, transaction_ids[], statement_balance, statement_date
   - Logic: Mark transactions reconciled, log discrepancy if any
   - Validation: calculated balance matches statement

### Database Changes:
- Add `status` column if missing (active/closed/archived)
- Add `closed_date` column if missing

### Testing Requirements:
- Opening/closing balance calculations
- Reconciliation matching logic
- Transfer between accounts integrity

---

## Phase 5: Advanced Features (Priority: LOW)
**Duration**: 3-5 days

### Tools to Implement:
1. **manage_holdings** - CRUD for investment holdings
   - create_holding, update_holding, delete_holding
   - Parameters: account_id, symbol, quantity, cost_basis, purchase_date

2. **create_recurring_transaction** - Set up recurring transaction
   - Parameters: template_id, frequency (daily/weekly/monthly), start_date, end_date
   - Logic: Create schedule for automatic transaction creation

3. **create_transfer** - Transfer between accounts
   - Parameters: from_account_id, to_account_id, amount, date, description
   - Logic: Create paired transactions with proper entries

4. **attach_receipt** - Attach file/image to transaction
   - Parameters: transaction_id, file_data (base64), filename, mime_type
   - Storage: Save to configured storage backend

5. **create_tags** - Create custom transaction tags
   - Parameters: name, color
   - Usage: Enhanced transaction filtering/reporting

### Database Changes:
- `holdings` table schema review
- `recurring_transactions` table creation
- `transaction_attachments` table creation
- `tags` and `transaction_tags` tables creation

### Testing Requirements:
- Holding cost basis calculations
- Recurring transaction scheduling logic
- Transfer paired-transaction integrity
- File upload/storage handling

---

## Implementation Guidelines

### Tool Structure Pattern (fast-mcp)
Each tool should follow this structure:

```ruby
# lib/surefinance_mcp/tools/handlers/create_category.rb
module SurefinanceMCP
  module Tools
    module Handlers
      class CreateCategory < FastMcp::Tool
        include SurefinanceMCP::Tools::BaseTool

        def self.tool_name
          "create_category"
        end

        def description
          "Create a new expense or income category"
        end

        def input_schema
          {
            type: "object",
            properties: {
              name: { type: "string", minLength: 1 },
              type: { type: "string", enum: ["expense", "income"] },
              parent_id: { type: "string", minLength: 1 },
              color: { type: "string", pattern: "^#[0-9A-Fa-f]{6}$" },
              icon: { type: "string", minLength: 1 }
            },
            required: ["name", "type"]
          }
        end

        def call(arguments:, **_context)
          family_id = server_context[:family_id]

          category = Models::Category.create!(
            family_id: family_id,
            name: arguments[:name],
            category_type: arguments[:type],
            parent_id: arguments[:parent_id],
            color: arguments[:color] || "#000000",
            icon: arguments[:icon] || "default"
          )

          {
            category: {
              id: category.id,
              name: category.name,
              type: category.category_type,
              parent_id: category.parent_id,
              color: category.color,
              icon: category.icon
            }
          }
        rescue ActiveRecord::RecordInvalid => e
          raise FastMcp::Error.new(
            code: -32602,
            message: "Validation failed: #{e.message}"
          )
        end
      end
    end
  end
end
```

### Error Handling Standards
- Use FastMcp::Error for MCP-compliant errors
- Validation errors: code -32602 (Invalid params)
- Not found errors: code -32001 (Resource not found)
- Conflict errors: code -32003 (Conflict)
- Server errors: code -32603 (Internal error)

### Testing Standards
Each tool must have:
1. **Unit test**: Test tool logic in isolation
2. **Integration test**: Test with real database (transaction rollback)
3. **Validation test**: Test input validation edge cases
4. **Error handling test**: Test error responses

Example test structure:
```ruby
# spec/surefinance_mcp/tools/handlers/create_category_spec.rb
RSpec.describe SurefinanceMCP::Tools::Handlers::CreateCategory do
  let(:family) { create(:family) }
  let(:server_context) { { family_id: family.id } }

  describe "#call" do
    it "creates a category with valid params" do
      result = described_class.new.call(
        arguments: { name: "Groceries", type: "expense" },
        server_context: server_context
      )

      expect(result[:category][:name]).to eq("Groceries")
      expect(Models::Category.count).to eq(1)
    end

    it "raises error for duplicate name" do
      create(:category, family: family, name: "Groceries")

      expect {
        described_class.new.call(
          arguments: { name: "Groceries", type: "expense" },
          server_context: server_context
        )
      }.to raise_error(FastMcp::Error, /duplicate/i)
    end
  end
end
```

---

## Documentation Requirements

For each phase, update:
1. **AGENT.md** - Add new tool descriptions and usage examples
2. **README.md** - Update feature list and API examples
3. **CHANGELOG.md** - Log all new tools and changes
4. **Integration tests** - Add end-to-end workflow tests

---

## Rollout Strategy

### Phase Rollout Process:
1. **Develop** - Implement tools following pattern
2. **Test** - Write and pass all tests
3. **Document** - Update all documentation
4. **Review** - Code review for quality/security
5. **Deploy** - Merge to main, deploy to staging
6. **Validate** - Test in staging environment
7. **Release** - Deploy to production

### Version Numbering:
- Phase 1 (Categories): v1.1.0
- Phase 2 (Budgets): v1.2.0
- Phase 3 (Transactions): v1.3.0
- Phase 4 (Accounts): v1.4.0
- Phase 5 (Advanced): v2.0.0

---

## Security Considerations

### Authorization:
- All tools must verify `family_id` from server context
- Use `FamilyScoped` concern to scope all queries
- Validate user has permission for operation (read/write/admin)

### Input Validation:
- Sanitize all string inputs
- Validate UUIDs and foreign keys exist
- Enforce business rules (budget allocations, date ranges, etc.)
- Rate limit write operations

### Audit Logging:
- Log all mutations (create/update/delete) with user context
- Include: timestamp, family_id, operation, resource, changes
- Store in `audit_logs` table for compliance

---

## Success Metrics

### Phase Completion Criteria:
- [ ] All planned tools implemented
- [ ] All tests passing (100% coverage for new code)
- [ ] Documentation complete and reviewed
- [ ] No regressions in existing tools
- [ ] Performance benchmarks met (< 100ms per operation)
- [ ] Security review passed

### Overall Goals:
- **30+ new tools** added across 5 phases
- **Full CRUD** for all core models
- **Production-ready** code quality
- **Complete test coverage** (>95%)
- **Comprehensive documentation** for developers and users

---

## Timeline Estimate

- **Phase 1**: Week 1-2 (Category Management)
- **Phase 2**: Week 2-3 (Budget Management)
- **Phase 3**: Week 3-5 (Transaction Management)
- **Phase 4**: Week 5-6 (Account Management)
- **Phase 5**: Week 7-9 (Advanced Features)

**Total**: ~9 weeks for complete feature parity

---

## Next Steps

1. ✅ Review and approve this plan
2. ⏳ Begin Phase 1: Category Management
3. ⏳ Set up test fixtures for new models
4. ⏳ Create tool handler templates
5. ⏳ Implement first tool: `create_category`

---

## Questions for Product Owner

1. **Priority confirmation**: Is Category Management the highest priority?
2. **Bulk operations**: Do we need bulk create/update/delete for any entities?
3. **Soft deletes**: Should deletions be soft (archived) or hard (permanent)?
4. **Undo functionality**: Should we support undo for mutations?
5. **Webhooks**: Should mutations trigger webhooks for external integrations?
6. **Rate limiting**: What are acceptable rate limits per family/user?
7. **File storage**: Where should transaction attachments be stored? (S3, local, etc.)
