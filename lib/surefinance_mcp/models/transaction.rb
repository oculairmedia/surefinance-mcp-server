# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class Transaction < ApplicationRecord
      self.table_name = "transactions"

      belongs_to :category, optional: true
      has_one :entry, as: :entryable
      has_one :account, through: :entry

      # Custom family scope since transactions don't have direct family_id
      # Using explicit SQL to avoid ActiveRecord trying to reference transactions.family_id
      scope :for_family, ->(family_id) {
        joins("INNER JOIN entries ON entries.entryable_id = transactions.id AND entries.entryable_type = 'Transaction'")
          .joins("INNER JOIN accounts ON accounts.id = entries.account_id")
          .where("accounts.family_id = ?", family_id)
      }

      # Helper methods to access family through association chain
      def family
        account&.family
      end

      def family_id
        account&.family_id
      end

      def category_name
        self[:category_name] || category&.name
      end
    end
  end
end
