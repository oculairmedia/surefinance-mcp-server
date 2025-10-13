# frozen_string_literal: true

require_relative "authentication/api_key_strategy"
require_relative "authentication/jwt_strategy"
require_relative "authentication/composite"

module SurefinanceMCP
  module Authentication
    module_function

    def build(logger: SurefinanceMCP.logger)
      strategies = [
        Authentication::ApiKeyStrategy.new(logger: logger),
        Authentication::JwtStrategy.new(logger: logger)
      ]

      Composite.new(strategies: strategies, logger: logger)
    end
  end
end
