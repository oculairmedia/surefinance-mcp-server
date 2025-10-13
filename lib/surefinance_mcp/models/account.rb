# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class Account < ActiveRecord::Base
      self.table_name = "accounts"

      def current_balance
        # Placeholder: ensure correct column naming
        self[:current_balance] || self[:balance]
      end
    end
  end
end
