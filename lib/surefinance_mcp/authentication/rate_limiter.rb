# frozen_string_literal: true

require "rack/attack"

module SurefinanceMCP
  module Authentication
    class RateLimiter
      FAMILY_LIMIT = Integer(ENV.fetch("RATE_LIMIT_FAMILY", 1000), exception: false) || 1000
      FAMILY_PERIOD = Integer(ENV.fetch("RATE_LIMIT_FAMILY_PERIOD", 3600), exception: false) || 3600
      IP_LIMIT = Integer(ENV.fetch("RATE_LIMIT_IP", 300), exception: false) || 300
      IP_PERIOD = Integer(ENV.fetch("RATE_LIMIT_IP_PERIOD", 300), exception: false) || 300

      def self.configure!(rack_builder)
        rack_builder.use Rack::Attack

        Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

        Rack::Attack.throttle("mcp/ip", limit: IP_LIMIT, period: IP_PERIOD) do |req|
          req.ip if req.path.start_with?("/")
        end

        Rack::Attack.throttle("mcp/family", limit: FAMILY_LIMIT, period: FAMILY_PERIOD) do |req|
          req.env["authenticated_family_id"]
        end
      end
    end
  end
end
