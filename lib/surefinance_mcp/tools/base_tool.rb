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

      # Standardized error response helpers
      def error_response(type:, code:, message:, fields: nil)
        {
          ok: false,
          error: {
            type: type,           # validation_error | not_found | internal | not_implemented
            code: code,           # tool.action_type (e.g., "budget.validation_error")
            message: message
          }.tap { |err| err[:fields] = fields if fields }
        }
      end

      def validation_error(message, fields = nil)
        tool_name = self.class.respond_to?(:tool_name) ? self.class.tool_name : "unknown"
        error_response(
          type: "validation_error",
          code: "#{tool_name}.invalid",
          message: message,
          fields: fields
        )
      end

      def not_found_error(message)
        tool_name = self.class.respond_to?(:tool_name) ? self.class.tool_name : "unknown"
        error_response(
          type: "not_found",
          code: "#{tool_name}.not_found",
          message: message
        )
      end

      def internal_error(message = "Internal error")
        tool_name = self.class.respond_to?(:tool_name) ? self.class.tool_name : "unknown"
        error_response(
          type: "internal",
          code: "#{tool_name}.internal",
          message: message
        )
      end

      def not_implemented_error(message)
        tool_name = self.class.respond_to?(:tool_name) ? self.class.tool_name : "unknown"
        error_response(
          type: "not_implemented",
          code: "#{tool_name}.not_implemented",
          message: message
        )
      end
    end
  end
end
