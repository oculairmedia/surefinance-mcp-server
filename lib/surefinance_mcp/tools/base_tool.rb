# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    module BaseTool
      private

      def server_context
        SurefinanceMCP.server.server_context
      end

      def logger
        server_context[:logger]
      end
    end
  end
end
