# frozen_string_literal: true

require "jwt"

module SurefinanceMCP
  module Authentication
    class JwtStrategy
      def initialize(secret: ENV["JWT_SECRET"], algorithm: "HS256", logger: SurefinanceMCP.logger)
        @secret = secret
        @algorithm = algorithm
        @logger = logger
      end

      def authenticate(request)
        return nil unless secret

        token = bearer_token(request)
        return nil unless token

        payload, = JWT.decode(token, secret, true, { algorithm: algorithm })
        { type: :jwt, payload: payload }
      rescue JWT::DecodeError => e
        logger.warn("JWT authentication failed: #{e.message}")
        nil
      end

      private

      attr_reader :secret, :algorithm, :logger

      def bearer_token(request)
        auth_header = request.get_header("HTTP_AUTHORIZATION")
        return nil unless auth_header&.start_with?("Bearer ")

        auth_header.split(" ", 2)[1]
      end
    end
  end
end
