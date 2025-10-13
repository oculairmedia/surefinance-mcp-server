# frozen_string_literal: true

require "active_record"

module SurefinanceMCP
  module Database
    module_function

    def build(logger: SurefinanceMCP.logger)
      config = Config.load_database_config
      ActiveRecord::Base.establish_connection(config)
      ActiveRecord::Base.logger = logger if config["log"]
      ActiveRecord::Base
    rescue StandardError => e
      logger.error("Failed to establish database connection: #{e.message}")
      raise
    end
  end
end
