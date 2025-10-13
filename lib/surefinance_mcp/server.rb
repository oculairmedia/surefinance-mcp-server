# frozen_string_literal: true

require "mcp"
require "rack"
require "rackup"
require "puma"
require "yaml"
require "erb"

require_relative "config"
require_relative "authentication"
require_relative "authentication/rate_limiter"
require_relative "database"
require_relative "models"
require_relative "tools/registry"
require_relative "tools/http_handler"
require_relative "resources/registry"
require_relative "resources/http_handler"

module SurefinanceMCP
  class Server
    def initialize(logger: SurefinanceMCP.logger)
      @logger = logger
      @config = Config.load_server_config
      @tool_registry = Tools::Registry.new(logger: @logger)
      @resource_registry = Resources::Registry.new(logger: @logger)
      @authenticator = Authentication.build(logger: @logger)
      @database = Database.build(logger: @logger)
    end

    def start
      @logger.info("Starting SureFinance MCP server on #{host}:#{port}")

      server_logger = @logger
      server_authenticator = @authenticator
      server_tool_handler = tool_handler
      server_resource_handler = resource_handler
      server_unauthorized = method(:unauthorized_response)

      app = Rack::Builder.new do
        use Rack::CommonLogger, server_logger
        use Rack::ContentType, "application/json"
        Authentication::RateLimiter.configure!(self)

        run lambda { |env|
          request = Rack::Request.new(env)

          # No authentication required - single user mode
          # Use the family_id from environment or default
          family_id = ENV.fetch("DEFAULT_FAMILY_ID", "87925f63-2ee1-46f8-bebd-ddab3b26e0cd")
          auth_context = { type: :none, family_id: family_id }

          env["authenticated_family_id"] = auth_context[:family_id]

          # Route based on path - MCP HTTP transport uses /mcp endpoint
          path = request.path

          # Handle /mcp prefix - strip it and route based on remaining path
          if path.start_with?("/mcp")
            # Remove /mcp prefix for routing logic
            stripped_path = path.sub(%r{^/mcp}, "")
            stripped_path = "/" if stripped_path.empty?

            # Determine handler based on stripped path
            if stripped_path.start_with?("/resources")
              server_resource_handler.call(request, auth_context)
            else
              server_tool_handler.call(request, auth_context)
            end
          elsif path.start_with?("/resources")
            server_resource_handler.call(request, auth_context)
          else
            server_tool_handler.call(request, auth_context)
          end
        }
      end

      Puma::Server.new(app).tap do |server|
        server.add_tcp_listener(host, port)
        server.run.join
      end
    end

    private

    attr_reader :logger, :tool_registry, :resource_registry, :authenticator, :database, :config

    def host
      config.fetch("host")
    end

    def port
      config.fetch("port")
    end

    def tool_handler
      @tool_handler ||= Tools::HttpHandler.new(
        registry: tool_registry,
        authenticator: authenticator,
        database: database,
        logger: logger
      )
    end

    def resource_handler
      @resource_handler ||= Resources::HttpHandler.new(
        registry: resource_registry,
        authenticator: authenticator,
        database: database,
        logger: logger
      )
    end

    def unauthorized_response
      [
        401,
        { "Content-Type" => "application/json" },
        [JSON.dump({ error: "Unauthorized" })]
      ]
    end
  end
end
