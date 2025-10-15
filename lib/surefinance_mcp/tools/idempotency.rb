# frozen_string_literal: true

require "oj"

module SurefinanceMCP
  module Tools
    # Idempotency wrapper for write operations
    #
    # Ensures that duplicate requests with the same idempotency key return the cached result
    # instead of performing the operation again. This prevents unintended duplicate writes
    # (e.g., creating the same transaction twice due to network retries).
    #
    # @example Basic usage in a tool
    #   def call(action:, idempotency_key: nil, **args)
    #     family_id = server_context[:family_id]
    #     tool_name = self.class.tool_name
    #
    #     Tools::Idempotency.with_idempotency(tool: tool_name, key: idempotency_key.to_s, family_id: family_id) do
    #       case action
    #       when "create" then create_resource(args)
    #       end
    #     end
    #   end
    #
    # @example Idempotent create operation
    #   # First call - executes block and caches result
    #   result1 = tool.call(action: "create", idempotency_key: "abc123", amount: 100)
    #   # => {ok: true, result: {id: "uuid-1", amount: 100}}
    #
    #   # Second call with same key - returns cached result without executing block
    #   result2 = tool.call(action: "create", idempotency_key: "abc123", amount: 100)
    #   # => {ok: true, result: {id: "uuid-1", amount: 100}} (same UUID, no new record)
    #
    #   # Third call with different key - executes block and creates new record
    #   result3 = tool.call(action: "create", idempotency_key: "xyz789", amount: 100)
    #   # => {ok: true, result: {id: "uuid-2", amount: 100}} (new UUID, new record)
    #
    # @example Without idempotency key (normal operation)
    #   # Missing or empty key - executes block normally without caching
    #   result = tool.call(action: "create", amount: 100)
    #   # => {ok: true, result: {id: "uuid-3", amount: 100}}
    #
    # Key Format Recommendations:
    # - Use UUIDs for client-generated keys: "550e8400-e29b-41d4-a716-446655440000"
    # - Combine operation + timestamp: "create-transaction-2025-01-15-12-00-00"
    # - Include user context: "user-123-create-account-abc"
    # - Keep keys under 255 characters
    #
    # Scoping:
    # - Idempotency keys are scoped to (tool, family_id, key)
    # - Same key for different tools creates separate records
    # - Same key for different families creates separate records
    #
    # Cache Duration:
    # - Cached results persist in the database indefinitely
    # - Clean up old keys periodically via background job if needed
    #
    # Error Handling:
    # - If the block raises an error, the result is NOT cached
    # - Retrying with the same key after an error will re-execute the block
    # - Only successful results (including {ok: false, error: ...}) are cached
    #
    module Idempotency
      module_function

      # Wraps a block with idempotency checking
      #
      # @param tool [String] Tool name (e.g., "transfer_ops", "budget_ops")
      # @param key [String] Idempotency key provided by the client
      # @param family_id [String, UUID] Family ID for scoping
      # @yield Block to execute if no cached result exists
      # @return [Hash] Result from the block or cached result
      #
      # @example
      #   Idempotency.with_idempotency(tool: "account_ops", key: "abc123", family_id: family.id) do
      #     {ok: true, result: {account_id: "new-uuid"}}
      #   end
      #
      def with_idempotency(tool:, key:, family_id:)
        # If key is missing or empty, skip idempotency and execute block normally
        return yield if key.to_s.strip.empty?

        # Check for existing idempotency record
        existing = Models::IdempotencyKey.where(tool: tool, family_id: family_id, key: key).first
        return Oj.load(existing.response_json, symbol_keys: true) if existing&.response_json

        # No existing record - execute block and cache result
        result = yield
        Models::IdempotencyKey.create!(tool: tool, family_id: family_id, key: key, response_json: Oj.dump(result))
        result
      end
    end
  end
end
