# frozen_string_literal: true

require "bundler/setup"
require "dotenv/load"
require "logger"
require_relative "surefinance_mcp/errors"
require_relative "surefinance_mcp/server"
require_relative "surefinance_mcp/models"

module SurefinanceMCP
  class << self
    def logger
      @logger ||= Logger.new($stdout, level: log_level, formatter: log_formatter)
    end

    def start
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
