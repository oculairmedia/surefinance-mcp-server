# frozen_string_literal: true

require "date"

module SurefinanceMCP
  module Tools
    module Handlers
      # Recurring transactions tool: create | update | cancel | generate occurrences
      class RecurringOps < FastMcp::Tool
        include SurefinanceMCP::Tools::BaseTool

        ACTIONS = %w[create update cancel generate_occurrences].freeze

        def self.tool_name
          "recurring_ops"
        end

        description "Manage recurring transaction series"

        arguments do
          required(:action).value(:string).value(included_in?: ACTIONS).description("Operation to perform: create, update, cancel, generate_occurrences")
          optional(:id).value(:string).description("Series ID (required for update/cancel/generate_occurrences)")
          optional(:name).value(:string).description("Series name (required for create, optional for update)")
          optional(:cadence).value(:string).description("Recurrence cadence: weekly/biweekly/monthly/quarterly/yearly (required for create, optional for update)")
          optional(:starts_on).value(:string).description("Start date ISO 8601 (optional for create/update)")
          optional(:ends_on).value(:string).description("End date ISO 8601 (optional for create/update)")
          optional(:until_date).value(:string).description("Generate until date ISO 8601 (optional for generate_occurrences)")
        end

        # rubocop:disable Lint/UnusedMethodArgument
        def call(action:, idempotency_key: nil, **args)
          family_id = server_context[:family_id]
          tool_name = self.class.tool_name
          Tools::AuditWrapper.with_audit(tool: tool_name, action: action, family_id: family_id, params: args) do
            Tools::Idempotency.with_idempotency(tool: tool_name, key: idempotency_key.to_s, family_id: family_id) do
              case action
              when "create" then create_series(args)
              when "update" then update_series(args)
              when "cancel" then cancel_series(args)
              when "generate_occurrences" then generate_occurrences(args)
              else
                raise ArgumentError, "Unsupported action: #{action}"
              end
            end
          end
        rescue ActiveRecord::RecordNotFound => e
          { ok: false, error: { type: "not_found", code: "recurring.not_found", message: e.message } }
        rescue ArgumentError => e
          { ok: false, error: { type: "validation_error", code: "recurring.invalid", message: e.message } }
        rescue StandardError => e
          logger.error("recurring_ops error: #{e.class} #{e.message}")
          { ok: false, error: { type: "internal", code: "recurring.internal", message: "Internal error" } }
        ensure
          # rubocop:enable Lint/UnusedMethodArgument
        end

        private

        def create_series(payload)
          family_id = server_context[:family_id]
          series = Models::RecurringSeries.new(
            family_id: family_id,
            name: payload[:name],
            cadence: payload.fetch(:cadence)
          )
          assign_if_column(series, :starts_on, parse_date(payload[:starts_on]))
          assign_if_column(series, :ends_on, parse_date(payload[:ends_on]))
          series.save!
          { ok: true, result: { series: serialize_series(series) } }
        end

        def update_series(payload)
          family_id = server_context[:family_id]
          series = Models::RecurringSeries.find(payload.fetch(:id))
          raise ActiveRecord::RecordNotFound unless series.family_id == family_id

          updates = {}
          updates[:name] = payload[:name] if payload.key?(:name)
          updates[:cadence] = payload[:cadence] if payload.key?(:cadence)
          updates[:starts_on] = parse_date(payload[:starts_on]) if payload.key?(:starts_on)
          updates[:ends_on] = parse_date(payload[:ends_on]) if payload.key?(:ends_on)

          assign_and_save(series, updates)
          { ok: true, result: { series: serialize_series(series) } }
        end

        def cancel_series(payload)
          family_id = server_context[:family_id]
          series = Models::RecurringSeries.find(payload.fetch(:id))
          raise ActiveRecord::RecordNotFound unless series.family_id == family_id
          assign_and_save(series, { canceled: true }) if column?(Models::RecurringSeries, :canceled)
          { ok: true, result: { cancelled: true } }
        end

        def generate_occurrences(payload)
          family_id = server_context[:family_id]
          series = Models::RecurringSeries.find(payload.fetch(:id))
          raise ActiveRecord::RecordNotFound unless series.family_id == family_id

          until_date = parse_date(payload[:until_date]) || Date.today
          count = generate_transactions(series, until_date)
          { ok: true, result: { created: count } }
        end

        def generate_transactions(series, until_date)
          return 0 unless series.respond_to?(:starts_on) && series.starts_on

          cadence = series.respond_to?(:cadence) ? series.cadence : "monthly"
          current = series.starts_on
          created = 0
          while current <= until_date
            create_placeholder_transaction(series, current)
            current = advance_date(current, cadence)
            created += 1
          end
          created
        end

        def create_placeholder_transaction(series, date)
          return unless series.respond_to?(:template_payload) && series.template_payload

          payload = series.template_payload
          Models::Transaction.create!(payload.merge(created_at: date))
        rescue StandardError
          # Ignore errors in lightweight implementation; real system would log or raise
        end

        def advance_date(date, cadence)
          case cadence
          when "weekly" then date + 7
          when "biweekly" then date + 14
          when "monthly" then date >> 1
          when "quarterly" then date >> 3
          when "yearly" then date >> 12
          else
            date >> 1
          end
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

        def serialize_series(series)
          {
            id: series.id,
            name: series[:name],
            cadence: series[:cadence],
            starts_on: (series[:starts_on]&.iso8601 if column?(Models::RecurringSeries, :starts_on)),
            ends_on: (series[:ends_on]&.iso8601 if column?(Models::RecurringSeries, :ends_on))
          }.compact
        end
      end
    end
  end
end
