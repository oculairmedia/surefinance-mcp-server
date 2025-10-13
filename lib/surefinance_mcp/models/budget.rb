# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class Budget < ActiveRecord::Base
      self.table_name = "budgets"

      has_many :budget_periods
    end
  end
end
