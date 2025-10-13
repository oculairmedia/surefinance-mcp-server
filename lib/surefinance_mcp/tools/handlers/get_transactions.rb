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
          family_id = context.fetch(:auth).fetch(:family_id)
          params = context[:arguments] || {}
          scope = Models::Transaction.for_family(family_id)
          scope = scope.joins(:entry)

          scope = scope.where(entries: { account_id: params[:account_id] }) if params[:account_id]
          scope = scope.where("entries.date >= ?", params[:start_date]) if params[:start_date]
          scope = scope.where("entries.date <= ?", params[:end_date]) if params[:end_date]
          limit = params[:limit] || DEFAULT_LIMIT

          scope.order("entries.date DESC").limit(limit).includes(:category, entry: :account).map do |tx|
            {
              id: tx.id,
              account_id: tx.account_id,
              date: tx.entry&.date&.iso8601,
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
