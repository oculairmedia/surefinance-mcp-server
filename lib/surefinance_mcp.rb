# frozen_string_literal: true

puts "=== SureFinance MCP Server Starting ==="
$stdout.flush

require "bundler/setup"
require "dotenv/load"
require "logger"
require_relative "surefinance_mcp/errors"
require_relative "surefinance_mcp/server"
require_relative "surefinance_mcp/models"
require_relative "surefinance_mcp/tools/audit_wrapper"
require_relative "surefinance_mcp/tools/idempotency"
require_relative "surefinance_mcp/tools/accounts_tools"

# Monkey patch FastMcp::Tool to add items to array schemas for OpenAI compatibility
puts "=== Patching FastMcp::Tool.input_schema for OpenAI compatibility ==="
module FastMcp
  class Tool
    class << self
      # Store the original input_schema method
      alias_method :input_schema_original, :input_schema

      # Override to add items to arrays
      def input_schema
        puts "=== input_schema called for #{name} ==="
        schema = input_schema_original
        puts "=== Original schema: #{schema.inspect[0..200]} ==="

        # Recursively add items to arrays
        add_items_to_arrays(schema)
        puts "=== Patched schema: #{schema.inspect[0..200]} ==="

        schema
      end

      private

      def add_items_to_arrays(obj)
        case obj
        when Hash
          # If this is an array without items, add a generic object items schema
          if obj[:type] == "array" && !obj[:items]
            puts "=== Adding items to array property ==="
            obj[:items] = { type: "object" }
          end
          # Recursively process nested hashes
          obj.each_value { |v| add_items_to_arrays(v) }
        when Array
          # Recursively process arrays
          obj.each { |item| add_items_to_arrays(item) }
        end
      end
    end
  end
end
puts "=== FastMcp::Tool patched successfully ==="

module SurefinanceMCP
  class << self
    def logger
      @logger ||= begin
        $stdout.sync = true  # Force immediate flushing
        Logger.new($stdout, level: log_level, formatter: log_formatter)
      end
    end

    def start
      # Inject server_context into BaseTool before server boots
      SurefinanceMCP::Tools::BaseTool.server_context = server.server_context
      server.start
    end

    def server
      @server ||= Server.new(logger: logger)
    end

    private

    def log_level
      level = ENV.fetch("LOG_LEVEL", "info").to_s.downcase
      Logger.const_get(level.upcase)
    rescue NameError
      Logger::INFO
    end

    def log_formatter
      format = ENV.fetch("LOG_FORMAT", "json").to_s
      return json_formatter if format.casecmp("json").zero?

      proc do |severity, datetime, progname, message|
        "#{datetime.utc.iso8601} #{severity} #{progname}: #{message}\n"
      end
    end

    def json_formatter
      require "oj"

      proc do |severity, datetime, progname, message|
        Oj.dump(
          severity: severity,
          timestamp: datetime.utc.iso8601,
          progname: progname,
          message: message
        ) + "\n"
      end
    end
  end
end

# Start the server when this file is run directly
SurefinanceMCP.start if __FILE__ == $PROGRAM_NAME
