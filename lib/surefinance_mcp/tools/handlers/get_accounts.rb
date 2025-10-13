# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    module Handlers
      class GetAccounts < FastMcp::Tool
        include SurefinanceMCP::Tools::BaseTool

        description "List all accounts with current balances"

        arguments do
          optional(:updated_since).filled(:string).description("Filter accounts updated after this timestamp (ISO 8601)")
        end

        def call(updated_since: nil)
          accounts = Models::Account
            .for_family(server_context[:family_id])
            .visible

          accounts = accounts.where("updated_at > ?", updated_since) if updated_since

          {
            accounts: accounts.order(:name).map do |account|
              {
                id: account.id,
                name: account.name,
                balance: account.current_balance,
                currency: account.currency
              }
            end
          }
        end
      end
    end
  end
end
