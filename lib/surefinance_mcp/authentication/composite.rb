# frozen_string_literal: true

module SurefinanceMCP
  module Authentication
    class Composite
      def initialize(strategies:, logger: SurefinanceMCP.logger)
        @strategies = strategies
        @logger = logger
      end

      def authenticate(request)
        strategies.each do |strategy|
          result = strategy.authenticate(request)
          next unless result

          return normalize(result)
        end

        logger.warn("Authentication failed for request: #{request.path}")
        nil
      end

      private

      attr_reader :strategies, :logger

      def normalize(result)
        return result if result.key?(:family_id)

        logger.warn("Authenticator returned result without family scope")
        nil
      end
    end
  end
end
