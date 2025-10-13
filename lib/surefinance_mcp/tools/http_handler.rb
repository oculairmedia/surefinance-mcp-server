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

      def call(request, auth_context = nil)
        @auth_context = auth_context || authenticator.authenticate(request)
        return unauthorized unless @auth_context

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

      def list_tools
        response(200, { tools: registry.list })
      end

      def invoke_tool(request)
        payload = parse_json(request.body.read)
        tool_name = payload.fetch("name")
        arguments = payload.fetch("arguments", {})

        tool = registry.find_tool(tool_name)
        unless tool
          return response(404, { error: "Tool not found: #{tool_name}" })
        end

        result = tool.call(arguments: symbolize_keys(arguments), auth: @auth_context)
        response(200, result)
      rescue JSON::ParserError => e
        response(400, { error: "Invalid JSON payload: #{e.message}" })
      rescue StandardError => e
        logger.error("Tool invocation failed: #{e.message}")
        logger.error(e.backtrace.join("\n"))
        response(500, { error: "Internal server error: #{e.message}" })
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