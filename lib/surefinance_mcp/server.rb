# frozen_string_literal: true

require "mcp"
require "rack"
require "rackup"
require "puma"
require "yaml"
require "erb"

require_relative "config"
require_relative "authentication"
require_relative "database"
require_relative "models"
require_relative "tools/registry"
require_relative "resources/registry"

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

      app = Rack::Builder.new do
        use Rack::CommonLogger, logger
        use Rack::ContentType, "application/json"

        run lambda { |env|
          request = Rack::Request.new(env)
          handler = request.path.start_with?("/resources") ? resource_handler : tool_handler
          handler.call(request)
        }
      end

      Rackup::Handler::Puma.run(app, Host: host, Port: port, config_files: [])
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
  end
end
