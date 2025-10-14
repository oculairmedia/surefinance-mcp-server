# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class BudgetCategory < ApplicationRecord
      self.table_name = "budget_categories"

      belongs_to :budget
      belongs_to :category

      def budgeted_spending
        self[:budgeted_spending] || 0
      end

      def actual_spending
        self[:actual_spending] || 0
      end

      def percent_spent
        return 0.0 if budgeted_spending.to_f <= 0.0

        (actual_spending.to_f / budgeted_spending.to_f) * 100.0
      end
    end
  end
end
