# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class Rule < ApplicationRecord
      include Concerns::FamilyScoped

      self.table_name = "rules"

      belongs_to :family
    end
  end
end
