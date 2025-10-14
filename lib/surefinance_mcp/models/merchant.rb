# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class Merchant < ApplicationRecord
      include Concerns::FamilyScoped

      self.table_name = "merchants"

      belongs_to :family
    end
  end
end
