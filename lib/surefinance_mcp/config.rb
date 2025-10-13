# frozen_string_literal: true

require "yaml"
require "erb"

module SurefinanceMCP
  module Config
    module_function

    def load_server_config
      load_yaml_file("config/server.yml")
    end

    def load_database_config
      load_yaml_file("config/database.yml")
    end

    def load_yaml_file(path)
      erb_evaluated = ERB.new(File.read(path)).result
      YAML.safe_load(erb_evaluated, aliases: true)
        .fetch(env) { raise "Missing configuration for environment: #{env}" }
    rescue Errno::ENOENT => e
      raise "Configuration file not found: #{path}: #{e.message}"
    end

    def env
      ENV.fetch("MCP_SERVER_ENV", "development")
    end
  end
end
