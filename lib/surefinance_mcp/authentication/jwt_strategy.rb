# frozen_string_literal: true

require "jwt"

module SurefinanceMCP
  module Authentication
    class JwtStrategy
      SUPPORTED_ALGORITHMS = %w[HS256].freeze

      def initialize(secret: ENV["JWT_SECRET"], algorithm: "HS256", logger: SurefinanceMCP.logger)
        @secret = secret
        @algorithm = algorithm
        @logger = logger
        @leeway = Integer(ENV.fetch("JWT_LEEWAY", 5), exception: false) || 5
      end

      def authenticate(request)
        return nil unless secret_present?

        token = bearer_token(request)
        return nil unless token

        payload, = JWT.decode(token, secret, true, decode_options)
        extracted = extract_auth(payload)
        return nil unless extracted

        extracted
      rescue JWT::DecodeError => e
        logger.warn("JWT authentication failed: #{e.message}")
        nil
      end

      private

      attr_reader :secret, :algorithm, :logger, :leeway

      def secret_present?
        secret && !secret.empty?
      end

      def decode_options
        {
          algorithm: algorithm,
          leeway: leeway,
          verify_iat: true,
          verify_expiration: true
        }
      end

      def bearer_token(request)
        auth_header = request.get_header("HTTP_AUTHORIZATION")
        return nil unless auth_header&.start_with?("Bearer ")

        auth_header.split(" ", 2)[1]
      end

      def extract_auth(payload)
        family_id = payload["family_id"] || payload["family"]
        user_id = payload["user_id"] || payload["sub"]
        return nil unless family_id

        {
          type: :jwt,
          family_id: Integer(family_id, exception: false),
          user_id: user_id
        }
      rescue StandardError => e
        logger.error("Failed to extract JWT auth context: #{e.message}")
        nil
      end
    end
  end
end
