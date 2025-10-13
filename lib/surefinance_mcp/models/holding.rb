# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class Holding < ApplicationRecord
      include Concerns::FamilyScoped

      self.table_name = "holdings"

      belongs_to :account

      delegate :family, :family_id, to: :account
    end
  end
end
