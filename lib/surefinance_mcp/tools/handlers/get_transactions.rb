# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    module Handlers
      class GetTransactions < FastMcp::Tool
        include SurefinanceMCP::Tools::BaseTool

        def self.tool_name
          "list_transactions"
        end

        description "Retrieve transactions with optional filters for account, date range, and limit"

        arguments do
          optional(:account_id).filled(:string).description("Filter by account ID")
          optional(:start_date).filled(:string).description("Filter transactions after this date (ISO 8601)")
          optional(:end_date).filled(:string).description("Filter transactions before this date (ISO 8601)")
          optional(:limit).filled(:integer).description("Maximum number of transactions to return (default: 100)")
        end

        def call(account_id: nil, start_date: nil, end_date: nil, limit: 100)
          scope = Models::Transaction
            .for_family(server_context[:family_id])
            .select("transactions.*, entries.account_id as entry_account_id, entries.date as entry_date, entries.amount as entry_amount, entries.name as entry_name")

          scope = scope.where("entries.account_id = ?", account_id) if account_id
          scope = scope.where("entries.date >= ?", start_date) if start_date
          scope = scope.where("entries.date <= ?", end_date) if end_date

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
        rescue StandardError => e
          logger.error("Failed to fetch transactions: #{e.message}")
          raise
        end
      end
    end
  end
end
