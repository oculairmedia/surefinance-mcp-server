# frozen_string_literal: true

require_relative "tool"
require_relative "handlers/get_categories"

module SurefinanceMCP
  module Tools
    class CategoriesTools
      def initialize(logger: SurefinanceMCP.logger)
        @logger = logger
      end

      def tools
        [get_categories]
      end

      private

      attr_reader :logger

      def get_categories
        Tool.new(
          name: "get_categories",
          description: "List categories with hierarchy",
          parameters: {
            type: "object",
            properties: {
              parent_id: { type: "string" }
            },
            additionalProperties: false
          },
          handler: Handlers::GetCategories.new(logger: logger)
        )
      end
    end
  end
end
