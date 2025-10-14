# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class Budget < ApplicationRecord
      include Concerns::FamilyScoped

      self.table_name = "budgets"

      belongs_to :family
      has_many :budget_categories, dependent: :destroy
      has_many :categories, through: :budget_categories

      def period_type
        days = (end_date - start_date).to_i
        case days
        when 0..40 then "monthly"
        when 41..120 then "quarterly"
        when 121..400 then "yearly"
        else "custom"
        end
      end

      def percent_of_budget_spent
        return 0 unless respond_to?(:budgeted_spending) && respond_to?(:actual_spending)
        return 0 if budgeted_spending.to_f <= 0

        (actual_spending.to_f / budgeted_spending.to_f) * 100.0
      end
    end
  end
end
