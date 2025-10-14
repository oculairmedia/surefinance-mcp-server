# frozen_string_literal: true

require "date"

module SurefinanceMCP
  module Tools
    module Handlers
      # Transfer management: create linked transactions between accounts
      class TransferOps < FastMcp::Tool
        include SurefinanceMCP::Tools::BaseTool

        ACTIONS = %w[create].freeze

        def self.tool_name
          "transfer_ops"
        end

        description "Create zero-sum transfers between two accounts (family scoped)"

        arguments do
          required(:action).value(:string).value(included_in?: ACTIONS).description("Operation to perform: create")
          optional(:from_account_id).value(:string).description("Source account ID (required for create)")
          optional(:to_account_id).value(:string).description("Destination account ID (required for create)")
          optional(:amount).value(:float).description("Transfer amount (required for create)")
          optional(:date).value(:string).description("Transfer date ISO 8601 (optional for create)")
          optional(:memo).value(:string).description("Transfer memo (optional for create)")
          optional(:description).value(:string).description("Transfer description (optional for create)")
        end

        # rubocop:disable Lint/UnusedMethodArgument
        def call(action:, idempotency_key: nil, **args)
          family_id = server_context[:family_id]
          tool_name = self.class.tool_name
          Tools::AuditWrapper.with_audit(tool: tool_name, action: action, family_id: family_id, params: args) do
            Tools::Idempotency.with_idempotency(tool: tool_name, key: idempotency_key.to_s, family_id: family_id) do
              case action
              when "create" then create_transfer(args)
              else
                raise ArgumentError, "Unsupported action: #{action}"
              end
            end
          end
        rescue ActiveRecord::RecordNotFound => e
          { ok: false, error: { type: "not_found", code: "transfer.not_found", message: e.message } }
        rescue ArgumentError => e
          { ok: false, error: { type: "validation_error", code: "transfer.invalid", message: e.message } }
        rescue StandardError => e
          logger.error("transfer_ops error: #{e.class} #{e.message}")
          { ok: false, error: { type: "internal", code: "transfer.internal", message: "Internal error" } }
        ensure
          # rubocop:enable Lint/UnusedMethodArgument
        end

        private

        def create_transfer(payload)
          family_id = server_context[:family_id]
          from_account = Models::Account.find_for_family!(family_id, payload.fetch(:from_account_id))
          to_account = Models::Account.find_for_family!(family_id, payload.fetch(:to_account_id))
          amount = payload.fetch(:amount).to_f
          raise ArgumentError, "Amount must be positive" unless amount.positive?

          date = payload[:date] ? Date.parse(payload[:date].to_s) : Date.today
          memo = payload[:memo]

          ActiveRecord::Base.transaction do
            debit = Models::Transaction.new
            assign_if_column(debit, :memo, memo)
            assign_if_column(debit, :amount, -amount) if column?(Models::Transaction, :amount)
            assign_if_column(debit, :amount_cents, to_cents(-amount)) if column?(Models::Transaction, :amount_cents)
            debit.save!

            credit = Models::Transaction.new
            assign_if_column(credit, :memo, memo)
            assign_if_column(credit, :amount, amount) if column?(Models::Transaction, :amount)
            assign_if_column(credit, :amount_cents, to_cents(amount)) if column?(Models::Transaction, :amount_cents)
            credit.save!

            Models::Entry.create!(account_id: from_account.id, entryable: debit, date: date, amount: -amount, name: payload[:description] || memo)
            Models::Entry.create!(account_id: to_account.id, entryable: credit, date: date, amount: amount, name: payload[:description] || memo)

            link_transactions(debit, credit)

            { ok: true, result: { debit_txn: serialize_transaction(debit), credit_txn: serialize_transaction(credit) } }
          end
        end

        def link_transactions(debit, credit)
          if column?(Models::Transaction, :transfer_transaction_id)
            debit.update!(transfer_transaction_id: credit.id)
            credit.update!(transfer_transaction_id: debit.id)
          end
        end

        def assign_if_column(record, attr, value)
          return unless column?(record.class, attr)
          record.send(:"#{attr}=", value)
        end

        def column?(ar_class, attr)
          ar_class.column_names.include?(attr.to_s)
        end

        def to_cents(amount)
          (amount.to_f * 100).round
        end

        def serialize_transaction(record)
          entry = record.entry || record.entries.first
          {
            id: record.id,
            account_id: entry&.account_id,
            amount: entry&.amount,
            date: entry&.date&.iso8601
          }.compact
        end
      end
    end
  end
end
