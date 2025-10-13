# frozen_string_literal: true

require "fast_mcp"
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

module SurefinanceMCP
  class Server
    DEFAULT_VERSION = "1.0.0"

    def initialize(logger: SurefinanceMCP.logger)
      @logger = logger
      @config = Config.load_server_config
      @authenticator = Authentication.build(logger: @logger)
      @database = Database.build(logger: @logger)
      @context = build_server_context
    end

    def start
      logger.info("Starting SureFinance MCP server on #{host}:#{port}")

      Puma::Server.new(app).tap do |server|
        server.add_tcp_listener(host, port)
        server.run.join
      end
    end

    def app
      @app ||= build_app
    end

    def server_context
      context
    end

    private

    attr_reader :logger, :authenticator, :database, :config, :context

    def build_app
      server_logger = logger
      server_context = context

      # Use FastMcp.rack_middleware to create the app
      FastMcp.rack_middleware(
        health_app,
        name: "surefinance-mcp",
        version: DEFAULT_VERSION,
        path_prefix: "/mcp",
        logger: server_logger,
        localhost_only: false
      ) do |mcp_server|
        # Register all tools
        Tools::AccountsTools.new.tools.each do |tool_class|
          mcp_server.register_tool(tool_class)
        end
      end
    end

    def health_app
      Rack::Builder.new do
        map "/health" do
          run lambda { |_env|
            [200, { "Content-Type" => "application/json" }, [JSON.dump({ status: "ok" })]]
          }
        end

        run lambda { |_env|
          [404, { "Content-Type" => "application/json" }, [JSON.dump({ error: "Not Found" })]]
        }
      end.to_app
    end

    def host
      config.fetch("host")
    end

    def port
      config.fetch("port")
    end

    def build_server_context
      {
        logger: logger,
        database: database,
        authenticator: authenticator,
        family_id: ENV.fetch("DEFAULT_FAMILY_ID", "87925f63-2ee1-46f8-bebd-ddab3b26e0cd")
      }
    end
  end
end
