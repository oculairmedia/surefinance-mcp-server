# SureFinance MCP Server - Bug Report & Resolution

## Overview
This document tracks database schema compatibility issues discovered with the SureFinance MCP server during testing and their complete resolution. The server provides financial data tools but initially had several critical database schema compatibility problems that prevented proper functionality.

## Root Cause Analysis

The MCP server was initially designed with its own database schema expectations, but the actual SureFinance production database has a different schema. The key insight was that **the MCP server needed to adapt to the existing SureFinance schema** rather than expecting the database to match its own assumptions.

## Issues Found & Resolved

### 1. SurefinanceMCPToolsHandlersGetAccounts - ✅ WORKING
**Status**: Functional from the start
**Test Result**: Successfully returns account data with current balances
**Details**: This tool worked correctly without any modifications.

---

### 2. SurefinanceMCPToolsHandlersGetTransactions - ✅ FIXED
**Original Status**: Critical Database Schema Mismatch
**Original Error**: `PG::UndefinedColumn: ERROR: column transactions.family_id does not exist`

**Root Cause**:
- The `transactions` table doesn't have a direct `family_id` column
- The actual data relationship is: `transactions` → `entries` (polymorphic) → `accounts` → `families`
- ActiveRecord's `delegate :family_id, to: :account` was causing AR to look for `transactions.family_id` in SQL queries
- The `has_one :account, through: :entry` association was being optimized by ActiveRecord in ways that referenced the non-existent column

**Solution**:
1. **Removed the `delegate` call** that confused ActiveRecord's query builder
2. **Rewrote `for_family` scope with explicit SQL joins**:
   ```ruby
   scope :for_family, ->(family_id) {
     joins("INNER JOIN entries ON entries.entryable_id = transactions.id AND entries.entryable_type = 'Transaction'")
       .joins("INNER JOIN accounts ON accounts.id = entries.account_id")
       .where("accounts.family_id = ?", family_id)
   }
   ```
3. **Added explicit SELECT to pull entry data** into the result set instead of using association traversal
4. **Changed handlers to use direct column access** with `tx[:entry_account_id]` syntax instead of `tx.entry&.account_id`

**Files Modified**:
- `lib/surefinance_mcp/models/transaction.rb:12-27` - Removed delegate, rewrote scope, added helper methods
- `lib/surefinance_mcp/tools/handlers/get_transactions.rb:18-46` - Added SELECT, changed data access pattern

**Test Result**: ✅ Successfully returns transactions with all fields populated

---

### 3. SurefinanceMCPToolsHandlersSearchTransactions - ✅ FIXED
**Original Status**: Critical Database Schema Mismatch
**Original Error**: Same as GetTransactions - `column transactions.family_id does not exist`

**Root Cause**: Same underlying issue as GetTransactions

**Solution**: Applied identical fix as GetTransactions:
- Explicit SQL joins in the query
- SELECT statement to pull entry data into result set
- Direct column access pattern in handler

**Files Modified**:
- `lib/surefinance_mcp/tools/handlers/search_transactions.rb:20-48` - Same pattern as GetTransactions

**Test Result**: ✅ Successfully searches and returns matching transactions

---

### 4. SurefinanceMCPToolsHandlersGetAccountBalanceHistory - ✅ FIXED
**Original Status**: Critical Table Name Mismatch
**Original Error**: `PG::UndefinedTable: ERROR: relation "account_balances" does not exist`

**Root Cause**:
- Model was configured to use table name `account_balances`
- Actual table in SureFinance database is named `balances`

**Solution**:
Single line change to use correct table name:
```ruby
self.table_name = "balances"  # was "account_balances"
```

**Files Modified**:
- `lib/surefinance_mcp/models/account_balance_history.rb:6` - Changed table_name

**Test Result**: ✅ Successfully returns 30-day balance history with 27 data points

---

### 5. SurefinanceMCPToolsHandlersGetBudgets - ✅ FIXED
**Original Status**: Critical Model/Schema Mismatch
**Original Error**: References to non-existent `budget_periods` table and `BudgetPeriod` model

**Root Cause**:
- The `budgets` table exists in the database
- The model was expecting a separate `budget_periods` table
- Actual schema uses `budget_categories` table with a different structure
- Each budget has multiple `budget_categories` (one per category), not time-based periods

**Solution**:
1. **Updated Budget model** to use `budget_categories` instead of `budget_periods`:
   ```ruby
   has_many :budget_categories, dependent: :destroy
   has_many :categories, through: :budget_categories
   ```

2. **Renamed model file** from `budget_period.rb` to define `BudgetCategory` class instead:
   ```ruby
   class BudgetCategory < ApplicationRecord
     self.table_name = "budget_categories"
     belongs_to :budget
     belongs_to :category
   end
   ```

3. **Added `period_type` method** to Budget model to calculate period from date range:
   ```ruby
   def period_type
     days = (end_date - start_date).to_i
     case days
     when 0..40 then "monthly"
     when 41..120 then "quarterly"
     when 121..400 then "yearly"
     else "custom"
     end
   end
   ```

4. **Rewrote GetBudgets handler** to work with actual schema structure and return budget metadata

**Files Modified**:
- `lib/surefinance_mcp/models/budget.rb:10-27` - Changed associations, added period_type method
- `lib/surefinance_mcp/models/budget_period.rb:4-10` - Renamed class to BudgetCategory
- `lib/surefinance_mcp/tools/handlers/get_budgets.rb:15-44` - Rewrote to use new structure
- `lib/surefinance_mcp/models.rb:12` - Added require for budget_period file

**Test Result**: ✅ Successfully returns budget data with period types and category counts

---

### 6. SurefinanceMCPToolsHandlersGetCategories - ✅ WORKING
**Status**: Functional from the start
**Test Result**: Successfully returns all transaction categories
**Details**: This tool worked correctly without any modifications.

---

## Testing Results

All tools now working successfully:

```
✅ GetAccounts: Returns account data with balances
✅ GetTransactions: Returns full transaction history with dates, amounts, descriptions, categories
✅ SearchTransactions: Searches transactions by description keyword
✅ GetAccountBalanceHistory: Returns time-series balance history
✅ GetBudgets: Returns budget data filtered by period type
✅ GetCategories: Returns transaction category hierarchy
```

**Success Rate**: 6/6 tools (100%) ✅

## Sample Output

### GetTransactions
```json
{
  "transactions": [
    {
      "id": "6534482d-f5ad-477f-8344-31ef45296043",
      "account_id": "c9629406-2688-4414-b88f-7f45c3cc1cbe",
      "date": "2025-10-10",
      "amount": 200.0,
      "description": "Bi-weekly grocery bill",
      "category": "Food & Drink"
    }
  ]
}
```

### GetAccountBalanceHistory
```json
{
  "account": {
    "id": "c9629406-2688-4414-b88f-7f45c3cc1cbe",
    "name": "RBC"
  },
  "balances": [
    {"date": "2025-09-14", "balance": 1299.0},
    {"date": "2025-09-25", "balance": 1099.0},
    {"date": "2025-10-10", "balance": 899.0}
  ]
}
```

## Key Lessons Learned

1. **Schema Adaptation is Critical**: MCP servers must adapt to existing database schemas, not expect schemas to match their models

2. **Beware of ActiveRecord Magic**: When working with complex associations, especially polymorphic relationships, ActiveRecord's query optimization can introduce unexpected column references

3. **Explicit SQL Sometimes Necessary**: For complex joins across polymorphic associations, explicit SQL joins are more reliable and predictable than ActiveRecord associations

4. **Docker Cache Can Hide Changes**: Always use `--no-cache` flag when rebuilding after model changes to ensure fresh code deployment

5. **Table Naming Conventions Vary**: Never assume standard Rails conventions - always verify actual table names in the production database

6. **Test Against Real Schema**: Development should use a database dump or schema that matches production to catch compatibility issues early

## Implementation Pattern

The successful pattern for handling the polymorphic transaction relationship:

```ruby
# In Model (transaction.rb)
scope :for_family, ->(family_id) {
  joins("INNER JOIN entries ON entries.entryable_id = transactions.id AND entries.entryable_type = 'Transaction'")
    .joins("INNER JOIN accounts ON accounts.id = entries.account_id")
    .where("accounts.family_id = ?", family_id)
}

# In Handler
scope = Models::Transaction
  .for_family(server_context[:family_id])
  .select("transactions.*, entries.account_id as entry_account_id, entries.date as entry_date, entries.amount as entry_amount, entries.name as entry_name")

transactions = scope.map do |tx|
  {
    id: tx.id,
    account_id: tx[:entry_account_id],  # Direct column access
    date: tx[:entry_date]&.iso8601,
    amount: tx[:entry_amount],
    description: tx[:entry_name],
    category: tx.category_name
  }
end
```

## Files Changed Summary

1. **Models**:
   - `lib/surefinance_mcp/models/transaction.rb` - Removed delegate, rewrote for_family scope, added helper methods
   - `lib/surefinance_mcp/models/account_balance_history.rb` - Fixed table name
   - `lib/surefinance_mcp/models/budget.rb` - Changed associations, added period_type method
   - `lib/surefinance_mcp/models/budget_period.rb` - Renamed class to BudgetCategory
   - `lib/surefinance_mcp/models.rb` - Added budget_period require

2. **Tool Handlers**:
   - `lib/surefinance_mcp/tools/handlers/get_transactions.rb` - Rewrote query with explicit SELECT
   - `lib/surefinance_mcp/tools/handlers/search_transactions.rb` - Rewrote query with explicit SELECT
   - `lib/surefinance_mcp/tools/handlers/get_budgets.rb` - Rewrote to use budget_categories

## Deployment Process

Critical deployment steps identified:

1. **Build without cache**: `docker-compose build --no-cache`
2. **Stop existing containers**: `docker-compose down`
3. **Start fresh**: `docker-compose up -d`
4. **Verify**: Test all tools through MCP interface

## Conclusion

All database compatibility issues have been successfully resolved by adapting the MCP server models and queries to match the existing SureFinance production database schema. The server now provides reliable access to all financial data through its six MCP tools.

**Final Status**: Production Ready ✅
