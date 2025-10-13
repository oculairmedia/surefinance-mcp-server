# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    module Handlers
      class GetAccountBalanceHistory
        def initialize(logger: SurefinanceMCP.logger)
          @logger = logger
        end

        def call(context)
          account_id = context.dig(:arguments, :account_id)
          range = context.dig(:arguments, :range) || "90d"

          account = Models::Account.find(account_id)
          history = Models::AccountBalanceHistory.for_account(account.id, range)

          {
            account: {
              id: account.id,
              name: account.name
            },
            balances: history.map do |point|
              {
                date: point.date.iso8601,
                balance: point.balance
              }
            end
          }
        rescue ActiveRecord::RecordNotFound
          raise MCP::Errors::NotFound, "Account not found"
        rescue StandardError => e
          logger.error("Failed to fetch account balance history: #{e.message}")
          raise
        end

        private

        attr_reader :logger
      end
    end
  end
end
