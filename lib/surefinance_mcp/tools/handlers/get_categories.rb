# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    module Handlers
      class GetCategories
        def initialize(logger: SurefinanceMCP.logger)
          @logger = logger
        end

        def call(context)
          parent_id = context.dig(:arguments, :parent_id)
          scope = Models::Category.all
          scope = scope.where(parent_id: parent_id) if parent_id

          scope.order(:name).map do |category|
            {
              id: category.id,
              name: category.name,
              parent_id: category.parent_id
            }
          end
        rescue StandardError => e
          logger.error("Failed to fetch categories: #{e.message}")
          raise
        end

        private

        attr_reader :logger
      end
    end
  end
end
