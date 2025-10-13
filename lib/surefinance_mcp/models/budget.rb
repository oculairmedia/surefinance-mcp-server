# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class Budget < ApplicationRecord
      include Concerns::FamilyScoped

      self.table_name = "budgets"

      belongs_to :family
      has_many :budget_periods, dependent: :destroy
    end
  end
end
