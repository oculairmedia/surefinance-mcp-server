# frozen_string_literal: true

require "securerandom"

module SurefinanceMCP
  module Tools
    module Handlers
      # Attach receipts to transactions (placeholder implementation without storage backend)
      class AttachmentOps < FastMcp::Tool
        include SurefinanceMCP::Tools::BaseTool

        ACTIONS = %w[attach_receipt remove_receipt].freeze

        def self.tool_name
          "attachment_ops"
        end

        description "Attach or remove transaction receipts (metadata only)"

        arguments do
          required(:action).value(:string).value(included_in?: ACTIONS).description("Operation to perform: attach_receipt, remove_receipt")
          optional(:transaction_id).value(:string).description("Transaction ID (required for attach_receipt/remove_receipt)")
          optional(:filename).value(:string).description("File name (optional for attach_receipt)")
          optional(:content_type).value(:string).description("MIME type (optional for attach_receipt)")
          optional(:size).value(:integer).description("File size in bytes (optional for attach_receipt)")
        end

        # rubocop:disable Lint/UnusedMethodArgument
        def call(action:, idempotency_key: nil, **args)
          family_id = server_context[:family_id]
          tool_name = self.class.tool_name
          Tools::AuditWrapper.with_audit(tool: tool_name, action: action, family_id: family_id, params: args) do
            Tools::Idempotency.with_idempotency(tool: tool_name, key: idempotency_key.to_s, family_id: family_id) do
              case action
              when "attach_receipt" then attach_receipt(args)
              when "remove_receipt" then remove_receipt(args)
              else
                raise ArgumentError, "Unsupported action: #{action}"
              end
            end
          end
        rescue ActiveRecord::RecordNotFound => e
          { ok: false, error: { type: "not_found", code: "attachment.not_found", message: e.message } }
        rescue ArgumentError => e
          { ok: false, error: { type: "validation_error", code: "attachment.invalid", message: e.message } }
        rescue StandardError => e
          logger.error("attachment_ops error: #{e.class} #{e.message}")
          { ok: false, error: { type: "internal", code: "attachment.internal", message: "Internal error" } }
        ensure
          # rubocop:enable Lint/UnusedMethodArgument
        end

        private

        def attach_receipt(payload)
          family_id = server_context[:family_id]
          transaction = Models::Transaction.find(payload.fetch(:transaction_id))
          ensure_transaction_family!(transaction, family_id)

          attachment_id = SecureRandom.uuid
          metadata = {
            attachment_id: attachment_id,
            filename: payload[:filename],
            content_type: payload[:content_type],
            size: payload[:size]
          }.compact

          # Real implementation would upload blob via Active Storage; here we just return metadata
          { ok: true, result: { attachment: metadata } }
        end

        def remove_receipt(payload)
          family_id = server_context[:family_id]
          transaction = Models::Transaction.find(payload.fetch(:transaction_id))
          ensure_transaction_family!(transaction, family_id)

          { ok: true, result: { removed: true } }
        end

        def ensure_transaction_family!(transaction, family_id)
          entry = transaction.entry || transaction.entries.first
          raise ActiveRecord::RecordNotFound unless entry&.account&.family_id == family_id
        end
      end
    end
  end
end
