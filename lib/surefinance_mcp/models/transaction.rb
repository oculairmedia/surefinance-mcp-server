# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class Transaction < ActiveRecord::Base
      self.table_name = "transactions"

      def category_name
        self[:category_name] || category&.name
      end

      belongs_to :account, optional: true
      belongs_to :category, optional: true
    end
  end
end
