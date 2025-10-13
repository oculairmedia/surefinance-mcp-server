# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class Category < ApplicationRecord
      include Concerns::FamilyScoped

      self.table_name = "categories"

      belongs_to :family
      belongs_to :parent, class_name: "Category", optional: true
      has_many :children, class_name: "Category", foreign_key: :parent_id
    end
  end
end
