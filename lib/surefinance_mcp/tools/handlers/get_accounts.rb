# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    module Handlers
      class GetAccounts
        def initialize(logger: SurefinanceMCP.logger)
          @logger = logger
        end

        def call(context)
          accounts = Models::Account.all

          {
            accounts: accounts.map do |account|
              {
                id: account.id,
                name: account.name,
                balance: account.current_balance,
                currency: account.currency
              }
            end
          }
        rescue StandardError => e
          logger.error("Failed to fetch accounts: #{e.message}")
          raise
        end

        private

        attr_reader :logger
      end
    end
  end
end
