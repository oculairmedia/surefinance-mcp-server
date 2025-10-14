# frozen_string_literal: true

require_relative "base_tool"
require_relative "handlers/get_accounts"
require_relative "handlers/get_transactions"
require_relative "handlers/search_transactions"
require_relative "handlers/get_account_balance_history"
require_relative "handlers/get_budgets"
require_relative "handlers/budget_ops"
require_relative "handlers/account_ops"
require_relative "handlers/transaction_ops"
require_relative "handlers/transfer_ops"
require_relative "handlers/recurring_ops"
require_relative "handlers/asset_ops"
require_relative "handlers/attachment_ops"
require_relative "handlers/get_categories"
require_relative "handlers/category_ops"
require_relative "handlers/rule_ops"

module SurefinanceMCP
  module Tools
    class AccountsTools
      def tools
        [
          Handlers::GetAccounts,
          Handlers::GetTransactions,
          Handlers::SearchTransactions,
          Handlers::GetAccountBalanceHistory,
          Handlers::GetBudgets,
          Handlers::BudgetOps,
          Handlers::AccountOps,
          Handlers::TransactionOps,
          Handlers::TransferOps,
          Handlers::RecurringOps,
          Handlers::AssetOps,
          Handlers::AttachmentOps,
          Handlers::GetCategories,
          Handlers::CategoryOps,
          Handlers::RuleOps
        ]
      end
    end
  end
end
