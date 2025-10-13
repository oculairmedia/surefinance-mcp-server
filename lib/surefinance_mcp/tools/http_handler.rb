# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    class HttpHandler
      def initialize(registry:, authenticator:, database:, logger: SurefinanceMCP.logger)
        @registry = registry
        @authenticator = authenticator
        @database = database
        @logger = logger
      end

      def call(request)
        return unauthorized unless authenticated?(request)

        case request.request_method
        when "GET"
          list_tools
        when "POST"
          invoke_tool(request)
        else
          response(405, { error: "Method not allowed" })
        end
      end

      private

      attr_reader :registry, :authenticator, :database, :logger

      def authenticated?(request)
        @auth_context = authenticator.authenticate(request)
      end

      def list_tools
        response(200, { tools: registry.list })
      end

      def invoke_tool(request)
        payload = parse_json(request.body.read)
        tool_name = payload.fetch("name")
        arguments = payload.fetch("arguments", {})

        tool = registry.find_tool(tool_name)
        raise MCP::Errors::NotFound, "Tool not found" unless tool

        result = tool.call(arguments: symbolize_keys(arguments), auth: @auth_context)
        response(200, result)
      rescue MCP::Errors::NotFound => e
        response(404, { error: e.message })
      rescue JSON::ParserError
        response(400, { error: "Invalid JSON payload" })
      rescue StandardError => e
        logger.error("Tool invocation failed: #{e.message}")
        response(500, { error: "Internal server error" })
      end

      def parse_json(body)
        return {} if body.nil? || body.empty?

        JSON.parse(body)
      end

      def response(status, body)
        [status, { "Content-Type" => "application/json" }, [JSON.dump(body)]]
      end

      def unauthorized
        response(401, { error: "Unauthorized" })
      end

      def symbolize_keys(hash)
        hash.each_with_object({}) do |(key, value), memo|
          memo[key.to_sym] = value
        end
      end
    end
  end
end
}