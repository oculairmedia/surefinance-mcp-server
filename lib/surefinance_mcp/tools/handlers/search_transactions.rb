# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    module Handlers
      class SearchTransactions < FastMcp::Tool
        include SurefinanceMCP::Tools::BaseTool

        description "Search transactions by description text with optional account filter"

        arguments do
          required(:query).filled(:string).description("Search query to match against transaction descriptions")
          optional(:account_id).filled(:string).description("Filter by account ID")
          optional(:limit).filled(:integer).description("Maximum number of results to return (default: 50)")
        end

        def call(query:, account_id: nil, limit: 50)
          raise SurefinanceMCP::Errors::ValidationError, "query cannot be empty" if query.strip.empty?

          scope = Models::Transaction
            .for_family(server_context[:family_id])
            .where("transactions.description ILIKE ?", "%#{query}%")
            .joins(:entry)

          scope = scope.where(entries: { account_id: account_id }) if account_id

          transactions = scope
            .order("entries.date DESC")
            .limit(limit)
            .map do |tx|
              {
                id: tx.id,
                account_id: tx.entry&.account_id,
                date: tx.entry&.date&.iso8601,
                amount: tx.entry&.amount,
                description: tx.description,
                category: tx.category_name
              }
            end

          { transactions: transactions }
        rescue SurefinanceMCP::Errors::ValidationError
          raise
        rescue StandardError => e
          logger.error("Failed to search transactions: #{e.message}")
          raise
        end
      end
    end
  end
end
