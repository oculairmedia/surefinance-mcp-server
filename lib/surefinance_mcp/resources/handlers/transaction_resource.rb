# frozen_string_literal: true

require_relative "../resource"

module SurefinanceMCP
  module Resources
    module Handlers
      class TransactionResource < Resource
        def initialize(logger: SurefinanceMCP.logger)
          super(
            scheme: "surefinance",
            path_pattern: %r{^/transactions/([\w-]+)$},
            description: "Transaction details",
            logger: logger
          )
        end

        def call(uri, _context)
          transaction_id = uri.path.split("/").last
          transaction = Models::Transaction.find(transaction_id)

          {
            id: transaction.id,
            account_id: transaction.account_id,
            date: transaction.date.iso8601,
            amount: transaction.amount,
            description: transaction.description,
            category: transaction.category_name
          }
        rescue ActiveRecord::RecordNotFound
          raise MCP::Errors::NotFound, "Transaction not found"
        rescue StandardError => e
          logger.error("Failed to fetch transaction resource: #{e.message}")
          raise
        end
      end
    end
  end
end
