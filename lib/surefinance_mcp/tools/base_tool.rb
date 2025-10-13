# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    module BaseTool
      @server_context = nil

      class << self
        attr_accessor :server_context
      end

      private

      def server_context
        BaseTool.server_context
      end

      def logger
        server_context[:logger]
      end
    end
  end
end
