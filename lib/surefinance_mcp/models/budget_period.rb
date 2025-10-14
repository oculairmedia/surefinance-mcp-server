# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class BudgetCategory < ApplicationRecord
      self.table_name = "budget_categories"

      belongs_to :budget
      belongs_to :category
    end
  end
end
