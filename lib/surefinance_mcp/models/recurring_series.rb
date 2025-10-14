# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class RecurringSeries < ApplicationRecord
      include Concerns::FamilyScoped

      self.table_name = "recurring_series"

      belongs_to :family
    end
  end
end
