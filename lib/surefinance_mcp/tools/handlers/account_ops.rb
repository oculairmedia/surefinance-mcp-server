# frozen_string_literal: true

require "date"

module SurefinanceMCP
  module Tools
    module Handlers
      # Account management tool: create | update | close | reopen | reconcile
      class AccountOps < FastMcp::Tool
        include SurefinanceMCP::Tools::BaseTool

        ACTIONS = %w[create update close reopen reconcile].freeze

        def self.tool_name
          "account_ops"
        end

        description "Manage accounts: create, update, close, reopen, reconcile balances (family scoped)"

        arguments do
          required(:action).value(:string).value(included_in?: ACTIONS)
          required(:payload).value(:hash).hash do
            optional(:id).value(:string).description("Account ID (required for update/close/reopen/reconcile)")
            optional(:name).value(:string).description("Account name (required for create, optional for update)")
            optional(:type).value(:string).description("Account type (required for create, optional for update)")
            optional(:currency).value(:string).description("Currency code (optional for create/update)")
            optional(:opening_balance).value(:float).description("Opening balance (optional for create)")
            optional(:opened_on).value(:string).description("Opened date ISO 8601 (optional for create)")
            optional(:closed_on).value(:string).description("Closed date ISO 8601 (optional for close)")
            optional(:statement_date).value(:string).description("Statement date ISO 8601 (required for reconcile)")
            optional(:statement_balance).value(:float).description("Statement balance (required for reconcile)")
          end
          optional(:idempotency_key).value(:string)
        end

        # rubocop:disable Lint/UnusedMethodArgument
        def call(action:, payload:, idempotency_key: nil)
          family_id = server_context[:family_id]
          tool_name = self.class.tool_name
          Tools::AuditWrapper.with_audit(tool: tool_name, action: action, family_id: family_id, params: payload) do
            Tools::Idempotency.with_idempotency(tool: tool_name, key: idempotency_key.to_s, family_id: family_id) do
              case action
              when "create" then create_account(payload)
              when "update" then update_account(payload)
              when "close" then close_account(payload)
              when "reopen" then reopen_account(payload)
              when "reconcile" then reconcile_account(payload)
              else
                raise ArgumentError, "Unsupported action: #{action}"
              end
            end
          end
        rescue ActiveRecord::RecordNotFound => e
          { ok: false, error: { type: "not_found", code: "account.not_found", message: e.message } }
        rescue ActiveRecord::RecordInvalid => e
          { ok: false, error: { type: "validation_error", code: "account.invalid", message: e.record.errors.full_messages.join(", ") } }
        rescue ArgumentError => e
          { ok: false, error: { type: "validation_error", code: "account.invalid", message: e.message } }
        rescue StandardError => e
          logger.error("account_ops error: #{e.class} #{e.message}")
          { ok: false, error: { type: "internal", code: "account.internal", message: "Internal error" } }
        ensure
          # rubocop:enable Lint/UnusedMethodArgument
        end

        private

        def create_account(payload)
          family_id = server_context[:family_id]
          name = payload.fetch(:name)
          type = payload.fetch(:type)
          currency = payload[:currency]
          balance = payload[:opening_balance]
          opened_on = payload[:opened_on]

          account = Models::Account.new(
            family_id: family_id,
            name: name
          )
          assign_if_column(account, :currency, currency)
          assign_if_column(account, :accountable_type, type)
          assign_if_column(account, :balance, balance)
          assign_if_column(account, :cash_balance, balance)
          assign_if_column(account, :opened_on, parse_date(opened_on)) if opened_on

          account.save!
          { ok: true, result: { account: serialize_account(account) } }
        end

        def update_account(payload)
          family_id = server_context[:family_id]
          id = payload.fetch(:id)
          account = Models::Account.find_for_family!(family_id, id)

          updates = {}
          updates[:name] = payload[:name] if payload.key?(:name)
          updates[:accountable_type] = payload[:type] if payload.key?(:type) && column?(Models::Account, :accountable_type)
          updates[:currency] = payload[:currency] if payload.key?(:currency) && column?(Models::Account, :currency)

          assign_and_save(account, updates)
          { ok: true, result: { account: serialize_account(account) } }
        end

        def close_account(payload)
          family_id = server_context[:family_id]
          id = payload.fetch(:id)
          account = Models::Account.find_for_family!(family_id, id)

          assign_and_save(account, { status: "disabled", closed_on: parse_date(payload[:closed_on]) }) if column?(Models::Account, :status)
          { ok: true, result: { account: serialize_account(account) } }
        end

        def reopen_account(payload)
          family_id = server_context[:family_id]
          id = payload.fetch(:id)
          account = Models::Account.find_for_family!(family_id, id)

          assign_and_save(account, { status: "active", closed_on: nil }) if column?(Models::Account, :status)
          { ok: true, result: { account: serialize_account(account) } }
        end

        def reconcile_account(payload)
          family_id = server_context[:family_id]
          id = payload.fetch(:id)
          statement_date = parse_date(payload.fetch(:statement_date))
          statement_balance = payload.fetch(:statement_balance)

          account = Models::Account.find_for_family!(family_id, id)

          current_balance = account.respond_to?(:current_balance) ? account.current_balance.to_f : account[:balance].to_f
          diff = (statement_balance.to_f - current_balance)

          assign_and_save(account, { current_balance: statement_balance }) if column?(Models::Account, :current_balance)

          { ok: true, result: { diff: diff, account: serialize_account(account) } }
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

        def parse_date(value)
          return nil unless value
          Date.parse(value.to_s)
        end

        def serialize_account(account)
          {
            id: account.id,
            name: account.name,
            status: (account[:status] if column?(Models::Account, :status)),
            currency: (account[:currency] if column?(Models::Account, :currency)),
            balance: (account[:balance] if column?(Models::Account, :balance)),
            current_balance: (account[:current_balance] if column?(Models::Account, :current_balance)),
            accountable_type: (account[:accountable_type] if column?(Models::Account, :accountable_type))
          }.compact
        end
      end
    end
  end
end
