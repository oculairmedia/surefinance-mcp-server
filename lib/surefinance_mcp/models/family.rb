# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class Family < ApplicationRecord
      self.table_name = "families"

      has_many :accounts, dependent: :destroy
      has_many :entries, through: :accounts
      has_many :transactions, through: :accounts
      has_many :holdings, through: :accounts
      has_many :categories, dependent: :destroy
      has_many :budgets, dependent: :destroy

      validates :name, presence: true
    end
  end
end
