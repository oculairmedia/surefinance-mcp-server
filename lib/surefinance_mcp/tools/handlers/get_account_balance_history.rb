# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    module Handlers
      class GetAccountBalanceHistory < FastMcp::Tool
        include SurefinanceMCP::Tools::BaseTool

        description "Retrieve historical balance data for a specific account"

        arguments do
          required(:account_id).filled(:string).description("Account ID to retrieve balance history for")
          optional(:range).filled(:string).description("Time range for history (e.g., '90d', '1y', default: '90d')")
        end

        def call(account_id:, range: "90d")
          account = Models::Account.find_for_family!(server_context[:family_id], account_id)
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
          raise SurefinanceMCP::Errors::NotFound, "Account not found"
        rescue StandardError => e
          logger.error("Failed to fetch account balance history: #{e.message}")
          raise
        end
      end
    end
  end
end
