# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    class Registry
      def initialize(*); end

      def find_tool(*)
        warn "Tools::Registry is deprecated under Fast-MCP."
        nil
      end

      def list
        []
      end
    end
  end
end
