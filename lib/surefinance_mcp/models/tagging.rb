# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class Tagging < ApplicationRecord
      self.table_name = "taggings"

      belongs_to :tag
      belongs_to :taggable, polymorphic: true
    end
  end
end
