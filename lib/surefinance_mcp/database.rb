# frozen_string_literal: true

require "active_record"
require "active_support/dependencies"

module SurefinanceMCP
  module Database
    module_function

    def build(logger: SurefinanceMCP.logger)
      config = Config.load_database_config
      ActiveRecord::Base.establish_connection(config)
      ActiveRecord::Base.logger = logger if config["log"]
      require_models
      ActiveRecord::Base
    rescue StandardError => e
      logger.error("Failed to establish database connection: #{e.message}")
      raise
    end

    def require_models
      require_relative "models"
    end
  end
end
