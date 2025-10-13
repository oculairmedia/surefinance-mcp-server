# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    module Handlers
      class GetTransactions
        DEFAULT_LIMIT = 100

        def initialize(logger: SurefinanceMCP.logger)
          @logger = logger
        end

        def call(context)
          params = context[:arguments] || {}
          scope = Models::Transaction.all

          scope = scope.where(account_id: params[:account_id]) if params[:account_id]
          scope = scope.where("date >= ?", params[:start_date]) if params[:start_date]
          scope = scope.where("date <= ?", params[:end_date]) if params[:end_date]
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
        rescue StandardError => e
          logger.error("Failed to fetch transactions: #{e.message}")
          raise
        end

        private

        attr_reader :logger
      end
    end
  end
end
