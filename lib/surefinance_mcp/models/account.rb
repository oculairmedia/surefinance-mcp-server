# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class Account < ApplicationRecord
      include Concerns::FamilyScoped

      self.table_name = "accounts"

      belongs_to :family
      has_many :entries, dependent: :destroy
      has_many :transactions, through: :entries, source: :entryable, source_type: "Transaction"
      has_many :holdings, dependent: :destroy
      has_many :balances, class_name: "AccountBalanceHistory", dependent: :destroy

      scope :visible, -> { where(status: %w[active draft]) }

      def current_balance
        self[:current_balance] || self[:balance]
      end
    end
  end
end
