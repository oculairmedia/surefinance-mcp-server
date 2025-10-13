# frozen_string_literal: true

require_relative "resource"
require_relative "handlers/account_resource"
require_relative "handlers/transaction_resource"
require_relative "handlers/budget_resource"
require_relative "handlers/holding_resource"

module SurefinanceMCP
  module Resources
    class Registry
      def initialize(logger: SurefinanceMCP.logger)
        @logger = logger
        @resources = build_resources
      end

      def find(uri)
        resources.find { |resource| resource.match?(uri) }
      end

      def list
        resources.map(&:to_h)
      end

      private

      attr_reader :resources, :logger

      def build_resources
        [
          Handlers::AccountResource.new(logger: logger),
          Handlers::TransactionResource.new(logger: logger),
          Handlers::BudgetResource.new(logger: logger),
          Handlers::HoldingResource.new(logger: logger)
        ]
      end
    end
  end
end
