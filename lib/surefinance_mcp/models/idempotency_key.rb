# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class IdempotencyKey < ApplicationRecord
      self.table_name = "idempotency_keys"

      # Columns (expected):
      # - user_id: uuid (nullable if not tracked)
      # - family_id: uuid
      # - tool: string
      # - key: string
      # - response_json: text
      # - created_at: datetime

      validates :family_id, :tool, :key, presence: true
      validates :key, uniqueness: { scope: %i[family_id tool] }
    end
  end
end
