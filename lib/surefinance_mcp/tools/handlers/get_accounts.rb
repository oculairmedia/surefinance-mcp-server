# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    module Handlers
      class GetAccounts
        def initialize(logger: SurefinanceMCP.logger)
          @logger = logger
        end

        def call(context)
          family_id = context.fetch(:auth).fetch(:family_id)
          accounts = Models::Account.for_family(family_id).visible

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
