# frozen_string_literal: true

module SurefinanceMCP
  module Authentication
    class ApiKeyStrategy
      def initialize(header: "X-API-Key", secret: ENV["API_KEY"], logger: SurefinanceMCP.logger)
        @header = header
        @secret = secret
        @logger = logger
      end

      def authenticate(request)
        return nil unless secret

        provided = request.get_header("HTTP_#{header.upcase.tr('-', '_')}")
        return { type: :api_key } if provided && secure_compare(provided, secret)

        nil
      end

      private

      attr_reader :header, :secret, :logger

      def secure_compare(a, b)
        return false unless a && b

        Rack::Utils.secure_compare(a, b)
      rescue StandardError => e
        logger.error("API key comparison failed: #{e.message}")
        false
      end
    end
  end
end
