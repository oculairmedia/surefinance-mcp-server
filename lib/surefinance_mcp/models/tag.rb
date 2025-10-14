# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class Tag < ApplicationRecord
      include Concerns::FamilyScoped

      self.table_name = "tags"

      belongs_to :family
      has_many :taggings, dependent: :destroy
    end
  end
end
