# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class Budget < ApplicationRecord
      include Concerns::FamilyScoped

      self.table_name = "budgets"

      belongs_to :family
      has_many :budget_categories, dependent: :destroy
      has_many :categories, through: :budget_categories

      # Calculate the period type based on the date range
      def period_type
        days = (end_date - start_date).to_i
        case days
        when 0..40
          "monthly"
        when 41..120
          "quarterly"
        when 121..400
          "yearly"
        else
          "custom"
        end
      end
    end
  end
end
