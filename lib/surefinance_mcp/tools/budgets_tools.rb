# frozen_string_literal: true

require_relative "tool"
require_relative "handlers/get_budgets"

module SurefinanceMCP
  module Tools
    class BudgetsTools
      def initialize(logger: SurefinanceMCP.logger)
        @logger = logger
      end

      def tools
        [get_budgets]
      end

      private

      attr_reader :logger

      def get_budgets
        Tool.new(
          name: "get_budgets",
          description: "List budgets with spending analysis",
          parameters: {
            type: "object",
            properties: {
              period: {
                type: "string",
                enum: %w[monthly quarterly yearly],
                description: "Budget period type"
              }
            },
            additionalProperties: false
          },
          handler: Handlers::GetBudgets.new(logger: logger)
        )
      end
    end
  end
end
