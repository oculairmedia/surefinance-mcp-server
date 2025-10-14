# frozen_string_literal: true

require "set"

module SurefinanceMCP
  module Models
    class Category < ApplicationRecord
      include Concerns::FamilyScoped

      self.table_name = "categories"

      belongs_to :family
      belongs_to :parent, class_name: "Category", optional: true
      has_many :children, class_name: "Category", foreign_key: :parent_id
      has_many :budget_categories, dependent: :destroy

      validates :name, presence: true
      validates :name, uniqueness: { scope: :family_id }
      validates :color, presence: true, if: -> { column?(:color) }
      validates :lucide_icon, presence: true, if: -> { column?(:lucide_icon) }
      validate :category_level_limit
      validate :nested_category_matches_parent_classification

      before_save :inherit_color_from_parent

      scope :roots, -> { where(parent_id: nil) }
      scope :expenses, lambda {
        column?(:classification) ? where(classification: "expense") : all
      }
      scope :incomes, lambda {
        column?(:classification) ? where(classification: "income") : all
      }

      def parent?
        children.any?
      end

      def subcategory?
        parent.present?
      end

      def replace_and_destroy!(replacement)
        transaction do
          Models::Transaction.where(category_id: id).update_all(category_id: replacement&.id)
          destroy!
        end
      end

      private

      def inherit_color_from_parent
        return unless subcategory?
        return unless column?(:color) && parent&.respond_to?(:color)

        self.color = parent.color
      end

      def category_level_limit
        return unless subcategory? && parent&.subcategory?

        errors.add(:parent, "can't have more than 2 levels of subcategories")
      end

      def nested_category_matches_parent_classification
        return unless subcategory?
        return unless column?(:classification) && parent&.respond_to?(:classification)
        return if parent.classification == classification

        errors.add(:parent, "must have the same classification as its parent")
      end

      def column?(attr)
        self.class.column_names.include?(attr.to_s)
      end

      def self.table_exists_for?(name)
        ApplicationRecord.connection.data_source_exists?(name)
      rescue StandardError
        false
      end
    end
  end
end
