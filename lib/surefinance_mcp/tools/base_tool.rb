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

      # Numeric coercion helper - accepts integers, floats, and numeric strings
      def coerce_decimal(value, field_name: nil)
        return nil if value.nil?

        # Already a numeric type
        return BigDecimal(value.to_s) if value.is_a?(Numeric)

        # String conversion
        if value.is_a?(String)
          cleaned = value.strip
          return nil if cleaned.empty?
          return BigDecimal(cleaned)
        end

        # Try to convert other types
        BigDecimal(value.to_s)
      rescue ArgumentError, TypeError => e
        field_label = field_name ? " for #{field_name}" : ""
        raise ArgumentError, "Invalid numeric value#{field_label}: #{value.inspect}"
      end

      # Numeric serialization helper - converts BigDecimal/numeric values to float for JSON
      def serialize_numeric(value)
        return nil if value.nil?
        value.to_f
      end
    end
  end
end
