# frozen_string_literal: true

require_relative "tool"
require_relative "handlers/get_transactions"
require_relative "handlers/search_transactions"

module SurefinanceMCP
  module Tools
    class TransactionsTools
      def initialize(logger: SurefinanceMCP.logger)
        @logger = logger
      end

      def tools
        [get_transactions, search_transactions]
      end

      private

      attr_reader :logger

      def get_transactions
        Tool.new(
          name: "get_transactions",
          description: "Retrieve transactions with optional filters",
          parameters: {
            type: "object",
            properties: {
              account_id: {
                type: "string",
                description: "Filter transactions by account ID"
              },
              start_date: {
                type: "string",
                description: "Start date in ISO 8601 format (e.g., 2024-01-15)"
              },
              end_date: {
                type: "string",
                description: "End date in ISO 8601 format (e.g., 2024-12-31)"
              },
              limit: {
                type: "integer",
                description: "Maximum number of transactions to return",
                minimum: 1,
                maximum: 500
              }
            },
            additionalProperties: false
          },
          handler: Handlers::GetTransactions.new(logger: logger)
        )
      end

      def search_transactions
        Tool.new(
          name: "search_transactions",
          description: "Search transactions by keyword and filters",
          parameters: {
            type: "object",
            properties: {
              query: {
                type: "string",
                description: "Search keyword to match against transaction descriptions"
              },
              account_id: {
                type: "string",
                description: "Filter results by account ID"
              },
              limit: {
                type: "integer",
                description: "Maximum number of results to return",
                minimum: 1,
                maximum: 200
              }
            },
            required: ["query"],
            additionalProperties: false
          },
          handler: Handlers::SearchTransactions.new(logger: logger)
        )
      end
    end
  end
end