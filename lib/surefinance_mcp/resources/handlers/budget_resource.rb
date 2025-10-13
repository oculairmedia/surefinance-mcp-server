# frozen_string_literal: true

require_relative "../resource"

module SurefinanceMCP
  module Resources
    module Handlers
      class BudgetResource < Resource
        def initialize(logger: SurefinanceMCP.logger)
          super(
            scheme: "surefinance",
            path_pattern: %r{^/budgets/([\w-]+)$},
            description: "Budget details with spending breakdown",
            logger: logger
          )
        end

        def call(uri, _context)
          family_id = _context.fetch(:auth).fetch(:family_id)
          budget_id = uri.path.split("/").last
          budget = Models::Budget.find_for_family!(family_id, budget_id)
          periods = budget.budget_periods

          {
            id: budget.id,
            name: budget.name,
            periods: periods.map do |period|
              {
                period: period.period,
                amount: period.amount,
                spent: period.spent
              }
            end
          }
        rescue ActiveRecord::RecordNotFound
          raise SurefinanceMCP::Errors::NotFound, "Budget not found"
        rescue StandardError => e
          logger.error("Failed to fetch budget resource: #{e.message}")
          raise
        end
      end
    end
  end
end
