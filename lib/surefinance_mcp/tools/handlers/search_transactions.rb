# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    module Handlers
      class SearchTransactions
        DEFAULT_LIMIT = 50

        def initialize(logger: SurefinanceMCP.logger)
          @logger = logger
        end

        def call(context)
          params = context[:arguments] || {}
          query = params[:query]
          raise MCP::Errors::InvalidRequest, "query is required" unless query&.strip&.length&.positive?

          scope = Models::Transaction.where("description ILIKE ?", "%#{query}%")
          scope = scope.where(account_id: params[:account_id]) if params[:account_id]
          limit = params[:limit] || DEFAULT_LIMIT

          scope.limit(limit).map do |tx|
            {
              id: tx.id,
              account_id: tx.account_id,
              date: tx.date.iso8601,
              amount: tx.amount,
              description: tx.description,
              category: tx.category_name
            }
          end
        rescue MCP::Errors::InvalidRequest
          raise
        rescue StandardError => e
          logger.error("Failed to search transactions: #{e.message}")
          raise
        end

        private

        attr_reader :logger
      end
    end
  end
end
