# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class BudgetPeriod < ActiveRecord::Base
      self.table_name = "budget_periods"

      belongs_to :budget
    end
  end
end
