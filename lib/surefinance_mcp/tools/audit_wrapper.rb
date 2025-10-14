# frozen_string_literal: true

require "oj"

module SurefinanceMCP
  module Tools
    module AuditWrapper
      module_function

      def with_audit(tool:, action:, family_id:, actor_id: nil, params: {})
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        status = "success"
        result = nil
        begin
          result = yield
          result
        rescue => e
          status = "error"
          raise
        ensure
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
          Models::AuditLog.create!(
            actor_id: actor_id,
            family_id: family_id,
            tool: tool,
            action: action,
            params_json: Oj.dump(params),
            result_json: Oj.dump(result),
            status: status,
            duration_ms: duration_ms
          ) rescue nil
        end
      end
    end
  end
end
