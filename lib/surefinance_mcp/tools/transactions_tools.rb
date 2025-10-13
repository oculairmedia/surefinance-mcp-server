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
              account_id: { type: "string" },
              start_date: { type: "string", format: "date" },
              end_date: { type: "string", format: "date" },
              limit: { type: "integer", minimum: 1, maximum: 500 }
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
              query: { type: "string" },
              account_id: { type: "string" },
              limit: { type: "integer", minimum: 1, maximum: 200 }
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
}