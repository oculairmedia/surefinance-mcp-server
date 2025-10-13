# frozen_string_literal: true

require_relative "../resource"

module SurefinanceMCP
  module Resources
    module Handlers
      class AccountResource < Resource
        def initialize(logger: SurefinanceMCP.logger)
          super(
            scheme: "surefinance",
            path_pattern: %r{^/accounts/([\w-]+)$},
            description: "Account details with balance history",
            logger: logger
          )
        end

        def call(uri, _context)
          family_id = _context.fetch(:auth).fetch(:family_id)
          account_id = uri.path.split("/").last
          account = Models::Account.find_for_family!(family_id, account_id)
          history = Models::AccountBalanceHistory.for_account(account.id, "90d")

          {
            id: account.id,
            name: account.name,
            balance: account.current_balance,
            currency: account.currency,
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
          logger.error("Failed to fetch account resource: #{e.message}")
          raise
        end
      end
    end
  end
end
