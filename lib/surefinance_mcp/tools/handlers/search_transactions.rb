# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    module Handlers
      class SearchTransactions < FastMcp::Tool
        include SurefinanceMCP::Tools::BaseTool

        def self.tool_name
          "find_transactions"
        end

        description "Search transactions by description text with optional account filter"

        arguments do
          required(:query).value(:string).description("Search query to match against transaction descriptions")
          optional(:account_id).value(:string).description("Filter by account ID")
          optional(:limit).value(:integer).description("Maximum number of results to return (default: 50)")
        end

        def call(query:, account_id: nil, limit: 50)
          raise SurefinanceMCP::Errors::ValidationError, "query cannot be empty" if query.strip.empty?

          scope = Models::Transaction
            .for_family(server_context[:family_id])
            .select("transactions.*, entries.account_id as entry_account_id, entries.date as entry_date, entries.amount as entry_amount, entries.name as entry_name")
            .where("entries.name ILIKE ?", "%#{query}%")

          scope = scope.where("entries.account_id = ?", account_id) if account_id

          transactions = scope
            .order("entries.date DESC")
            .limit(limit)
            .includes(:category)
            .map do |tx|
              {
                id: tx.id,
                account_id: tx[:entry_account_id],
                date: tx[:entry_date]&.iso8601,
                amount: tx[:entry_amount],
                description: tx[:entry_name],
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
