# frozen_string_literal: true

require "bundler/setup"
require "dotenv/load"
require "rspec"
require "logger"

# Load core modules first (without models)
require_relative "../lib/surefinance_mcp/errors"
require_relative "../lib/surefinance_mcp/config"
require_relative "../lib/surefinance_mcp/database"

# Establish database connection for tests BEFORE loading models
SurefinanceMCP::Database.build(logger: Logger.new(nil))

# Now load the rest including models
require_relative "../lib/surefinance_mcp/models"
require_relative "../lib/surefinance_mcp/tools/base_tool"
require_relative "../lib/surefinance_mcp/tools/audit_wrapper"
require_relative "../lib/surefinance_mcp/tools/idempotency"
require_relative "../lib/surefinance_mcp/tools/handlers/transfer_ops"
require_relative "../lib/surefinance_mcp/tools/handlers/budget_ops"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Wrap each test in a transaction and roll it back
  config.around(:each) do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
