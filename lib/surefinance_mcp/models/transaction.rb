# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class Transaction < ApplicationRecord
      include Concerns::FamilyScoped

      self.table_name = "transactions"

      belongs_to :category, optional: true
      has_one :entry, as: :entryable
      has_one :account, through: :entry

      delegate :family, :family_id, to: :account, allow_nil: true

      def category_name
        self[:category_name] || category&.name
      end
    end
  end
end
