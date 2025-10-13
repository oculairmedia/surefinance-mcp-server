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
          family_id = context.fetch(:auth).fetch(:family_id)
          params = context[:arguments] || {}
          query = params[:query]
          raise SurefinanceMCP::Errors::InvalidRequest, "query is required" unless query&.strip&.length&.positive?

          scope = Models::Transaction.for_family(family_id)
                                      .where("transactions.description ILIKE ?", "%#{query}%")
                                      .joins(:entry)
          scope = scope.where(entries: { account_id: params[:account_id] }) if params[:account_id]
          limit = params[:limit] || DEFAULT_LIMIT

          scope.order("entries.date DESC").limit(limit).map do |tx|
            {
              id: tx.id,
              account_id: tx.entry&.account_id,
              date: tx.entry&.date&.iso8601,
              amount: tx.entry&.amount,
              description: tx.description,
              category: tx.category_name
            }
          end
        rescue SurefinanceMCP::Errors::InvalidRequest
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
