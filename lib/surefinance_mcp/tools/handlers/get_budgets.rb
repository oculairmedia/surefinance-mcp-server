# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    module Handlers
      class GetBudgets
        def initialize(logger: SurefinanceMCP.logger)
          @logger = logger
        end

        def call(context)
          period = context.dig(:arguments, :period) || "monthly"
          budgets = Models::Budget.includes(:budget_periods)

          budgets.map do |budget|
            period_data = budget.budget_periods.find_by(period: period)
            {
              id: budget.id,
              name: budget.name,
              amount: period_data&.amount
            }
          end
        rescue StandardError => e
          logger.error("Failed to fetch budgets: #{e.message}")
          raise
        end

        private

        attr_reader :logger
      end
    end
  end
end
