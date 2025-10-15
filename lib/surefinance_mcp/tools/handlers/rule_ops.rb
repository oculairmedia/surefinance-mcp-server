# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    module Handlers
      # Simplified rule management for transaction resources
      class RuleOps < FastMcp::Tool
        include SurefinanceMCP::Tools::BaseTool

        ACTIONS = %w[create update delete run].freeze

        def self.tool_name
          "rule_ops"
        end

        description "Manage simple transaction rules (create/update/delete/run)"

        arguments do
          required(:action).value(:string).value(included_in?: ACTIONS).description("Operation to perform: create, update, delete, run")
          optional(:id).value(:string).description("Rule ID (required for update/delete/run)")
          optional(:name).value(:string).description("Rule name (required for create, optional for update)")
          optional(:description).value(:string).description("Rule description (optional for create/update)")
        end

        # rubocop:disable Lint/UnusedMethodArgument
        def call(action:, idempotency_key: nil, **args)
          family_id = server_context[:family_id]
          tool_name = self.class.tool_name
          Tools::AuditWrapper.with_audit(tool: tool_name, action: action, family_id: family_id, params: args) do
            Tools::Idempotency.with_idempotency(tool: tool_name, key: idempotency_key.to_s, family_id: family_id) do
              case action
              when "create" then create_rule(args)
              when "update" then update_rule(args)
              when "delete" then delete_rule(args)
              when "run" then run_rule(args)
              else
                raise ArgumentError, "Unsupported action: #{action}"
              end
            end
          end
        rescue ActiveRecord::RecordNotFound => e
          { ok: false, error: { type: "not_found", code: "rule.not_found", message: e.message } }
        rescue ActiveRecord::RecordInvalid => e
          { ok: false, error: { type: "validation_error", code: "rule.invalid", message: e.record.errors.full_messages.join(", ") } }
        rescue ArgumentError => e
          { ok: false, error: { type: "validation_error", code: "rule.invalid", message: e.message } }
        rescue StandardError => e
          logger.error("rule_ops error: #{e.class} #{e.message}")
          { ok: false, error: { type: "internal", code: "rule.internal", message: "Internal error" } }
        ensure
          # rubocop:enable Lint/UnusedMethodArgument
        end

        private

        def create_rule(payload)
          family_id = server_context[:family_id]
          rule = Models::Rule.new(
            family_id: family_id,
            name: payload[:name],
            resource_type: "transaction"
          )
          assign_if_column(rule, :description, payload[:description])
          rule.save!
          { ok: true, result: { rule: serialize_rule(rule) } }
        end

        def update_rule(payload)
          family_id = server_context[:family_id]
          rule = Models::Rule.find(payload.fetch(:id))
          raise ActiveRecord::RecordNotFound unless rule.family_id == family_id

          updates = {}
          updates[:name] = payload[:name] if payload.key?(:name)
          updates[:description] = payload[:description] if payload.key?(:description) && column?(Models::Rule, :description)
          assign_and_save(rule, updates)

          { ok: true, result: { rule: serialize_rule(rule) } }
        end

        def delete_rule(payload)
          family_id = server_context[:family_id]
          rule = Models::Rule.find(payload.fetch(:id))
          raise ActiveRecord::RecordNotFound unless rule.family_id == family_id
          resource_id = rule.id
          rule.destroy!
          { ok: true, result: { deleted: true, resource_id: resource_id, resource_type: "rule" } }
        end

        def run_rule(payload)
          family_id = server_context[:family_id]
          rule = Models::Rule.find(payload.fetch(:id))
          raise ActiveRecord::RecordNotFound unless rule.family_id == family_id

          rule.apply
          { ok: true, result: { applied: true } }
        end

        def assign_if_column(record, attr, value)
          return unless column?(record.class, attr)
          record.send(:"#{attr}=", value)
        end

        def assign_and_save(record, attrs)
          attrs.each { |k, v| assign_if_column(record, k, v) }
          record.save!
        end

        def column?(ar_class, attr)
          ar_class.column_names.include?(attr.to_s)
        end

        def serialize_rule(rule)
          {
            id: rule.id,
            name: rule.name,
            resource_type: rule.resource_type
          }
        end
      end
    end
  end
end
