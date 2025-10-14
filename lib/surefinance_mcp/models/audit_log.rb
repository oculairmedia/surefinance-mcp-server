# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class AuditLog < ApplicationRecord
      self.table_name = "audit_logs"

      # Columns (expected):
      # - actor_id: uuid (nullable)
      # - family_id: uuid
      # - tool: string
      # - action: string
      # - params_json: text
      # - result_json: text
      # - status: string (success|error)
      # - duration_ms: integer
      # - created_at: datetime
    end
  end
end
