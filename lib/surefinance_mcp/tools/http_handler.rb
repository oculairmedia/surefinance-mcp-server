# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    class HttpHandler
      def initialize(*)
        warn "Tools::HttpHandler is deprecated under Fast-MCP. Use FastMcp::RackAdapter."
      end

      def call(*)
        raise "Tools::HttpHandler is no longer supported."
      end
    end
  end
end
