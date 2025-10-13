# frozen_string_literal: true

require_relative "base_tool"
require_relative "handlers/get_accounts"
require_relative "handlers/get_transactions"
require_relative "handlers/search_transactions"
require_relative "handlers/get_account_balance_history"
require_relative "handlers/get_budgets"
require_relative "handlers/get_categories"

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
          Handlers::GetCategories
        ]
      end
    end
  end
end
