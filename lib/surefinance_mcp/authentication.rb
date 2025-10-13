# frozen_string_literal: true

require_relative "authentication/api_key_strategy"
require_relative "authentication/jwt_strategy"

module SurefinanceMCP
  module Authentication
    module_function

    def build(logger: SurefinanceMCP.logger)
      strategies = [
        Authentication::ApiKeyStrategy.new(logger: logger),
        Authentication::JwtStrategy.new(logger: logger)
      ]

      Composite.new(strategies: strategies, logger: logger)
    end

    class Composite
      def initialize(strategies:, logger: SurefinanceMCP.logger)
        @strategies = strategies
        @logger = logger
      end

      def authenticate(request)
        strategies.each do |strategy|
          result = strategy.authenticate(request)
          return result if result
        end

        logger.warn("Authentication failed for request: #{request.path}")
        nil
      end

      private

      attr_reader :strategies, :logger
    end
  end
end
