# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class BudgetPeriod < ApplicationRecord
      self.table_name = "budget_periods"

      belongs_to :budget
    end
  end
end
