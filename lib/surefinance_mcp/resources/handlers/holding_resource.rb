# frozen_string_literal: true

require_relative "../resource"

module SurefinanceMCP
  module Resources
    module Handlers
      class HoldingResource < Resource
        def initialize(logger: SurefinanceMCP.logger)
          super(
            scheme: "surefinance",
            path_pattern: %r{^/holdings/([\w-]+)$},
            description: "Investment holding details",
            logger: logger
          )
        end

        def call(uri, _context)
          holding_id = uri.path.split("/").last
          holding = Models::Holding.find(holding_id)

          {
            id: holding.id,
            account_id: holding.account_id,
            symbol: holding.symbol,
            quantity: holding.quantity,
            market_value: holding.market_value
          }
        rescue ActiveRecord::RecordNotFound
          raise MCP::Errors::NotFound, "Holding not found"
        rescue StandardError => e
          logger.error("Failed to fetch holding resource: #{e.message}")
          raise
        end
      end
    end
  end
end
