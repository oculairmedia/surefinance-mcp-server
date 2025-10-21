# frozen_string_literal: true

require_relative "tool"
require_relative "handlers/get_accounts"
require_relative "handlers/get_account_balance_history"

module SurefinanceMCP
  module Tools
    class AccountsTools
      def initialize(logger: SurefinanceMCP.logger)
        @logger = logger
      end

      def tools
        [get_accounts, get_account_balance_history]
      end

      private

      attr_reader :logger

      def get_accounts
        Tool.new(
          name: "get_accounts",
          description: "List all accounts with current balances",
          parameters: {
            type: "object",
            properties: {
              updated_since: {
                type: "string",
                description: "ISO 8601 date-time string (e.g., 2024-01-15T10:30:00Z)"
              }
            },
            additionalProperties: false
          },
          handler: Handlers::GetAccounts.new(logger: logger)
        )
      end

      def get_account_balance_history
        Tool.new(
          name: "get_account_balance_history",
          description: "Retrieve balance history for a specific account",
          parameters: {
            type: "object",
            properties: {
              account_id: {
                type: "string",
                description: "The unique identifier of the account"
              },
              range: {
                type: "string",
                enum: %w[30d 90d 1y],
                description: "Time range for balance history"
              }
            },
            required: ["account_id"],
            additionalProperties: false
          },
          handler: Handlers::GetAccountBalanceHistory.new(logger: logger)
        )
      end
    end
  end
end
