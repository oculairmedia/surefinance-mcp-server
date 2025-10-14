# frozen_string_literal: true

require "oj"

module SurefinanceMCP
  module Tools
    module Idempotency
      module_function

      def with_idempotency(tool:, key:, family_id:)
        return yield if key.to_s.strip.empty?

        existing = Models::IdempotencyKey.where(tool: tool, family_id: family_id, key: key).first
        return Oj.load(existing.response_json, symbol_keys: true) if existing&.response_json

        result = yield
        Models::IdempotencyKey.create!(tool: tool, family_id: family_id, key: key, response_json: Oj.dump(result))
        result
      end
    end
  end
end
