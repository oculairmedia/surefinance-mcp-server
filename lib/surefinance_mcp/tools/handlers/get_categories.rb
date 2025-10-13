# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    module Handlers
      class GetCategories < FastMcp::Tool
        include SurefinanceMCP::Tools::BaseTool

        description "List all transaction categories with optional parent filter"

        arguments do
          optional(:parent_id).filled(:string).description("Filter by parent category ID (omit to list all categories)")
        end

        def call(parent_id: nil)
          scope = Models::Category.for_family(server_context[:family_id])
          scope = scope.where(parent_id: parent_id) if parent_id

          {
            categories: scope.order(:name).map do |category|
              {
                id: category.id,
                name: category.name,
                parent_id: category.parent_id
              }
            end
          }
        rescue StandardError => e
          logger.error("Failed to fetch categories: #{e.message}")
          raise
        end
      end
    end
  end
end
