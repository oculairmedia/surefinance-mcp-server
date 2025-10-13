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
      @mcp_server = FastMcp::Server.new(name: "surefinance-mcp", version: DEFAULT_VERSION)
    end

    def start
      logger.info("Starting SureFinance MCP server on #{host}:#{port}")

      Authentication::RateLimiter.configure!(rack_builder)

      Puma::Server.new(app).tap do |server|
        server.add_tcp_listener(host, port)
        server.run.join
      end
    end

    def app
      @app ||= rack_builder.to_app
    end

    def register_tool(tool_class)
      mcp_server.register_tool(tool_class)
    end

    def server_context
      context
    end

    private

    attr_reader :logger, :authenticator, :database, :config, :mcp_server, :context

    def rack_builder
      server_logger = logger
      server_mcp_server = mcp_server

      @rack_builder ||= Rack::Builder.new do
        use Rack::CommonLogger, server_logger
        use Rack::ContentType, "application/json"

        map "/mcp" do
          run FastMcp::RackAdapter.new(server: server_mcp_server)
        end

        map "/health" do
          run lambda { |_env|
            [200, { "Content-Type" => "application/json" }, [JSON.dump({ status: "ok" })]]
          }
        end
      end
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
