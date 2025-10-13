# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    module Handlers
      class GetBudgets < FastMcp::Tool
        include SurefinanceMCP::Tools::BaseTool

        description "List all budgets with amounts for a specific period"

        arguments do
          optional(:period).filled(:string).description("Budget period (e.g., 'monthly', 'yearly', default: 'monthly')")
        end

        def call(period: "monthly")
          budgets = Models::Budget
            .for_family(server_context[:family_id])
            .includes(:budget_periods)

          {
            budgets: budgets.map do |budget|
              period_data = budget.budget_periods.find_by(period: period)
              {
                id: budget.id,
                name: budget.name,
                amount: period_data&.amount
              }
            end
          }
        rescue StandardError => e
          logger.error("Failed to fetch budgets: #{e.message}")
          raise
        end
      end
    end
  end
end
