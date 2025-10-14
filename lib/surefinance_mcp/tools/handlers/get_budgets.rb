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
            .includes(:budget_categories, :categories)
            .order(start_date: :desc)

          filtered_budgets = if period && period != "all"
            budgets.select { |b| b.period_type == period }
          else
            budgets
          end

          {
            budgets: filtered_budgets.map do |budget|
              {
                id: budget.id,
                start_date: budget.start_date.iso8601,
                end_date: budget.end_date.iso8601,
                period_type: budget.period_type,
                budgeted_spending: budget.budgeted_spending,
                expected_income: budget.expected_income,
                currency: budget.currency,
                category_count: budget.budget_categories.size
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
