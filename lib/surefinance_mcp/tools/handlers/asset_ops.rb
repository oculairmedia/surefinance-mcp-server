# frozen_string_literal: true

require "date"

module SurefinanceMCP
  module Tools
    module Handlers
      # Asset tools: holdings, tag management, rule stubs
      class AssetOps < FastMcp::Tool
        include SurefinanceMCP::Tools::BaseTool

        ACTIONS = %w[
          create_holding update_holding delete_holding
          create_tag delete_tag assign_tag remove_tag
          create_rule update_rule delete_rule run_rule
        ].freeze

        def self.tool_name
          "asset_ops"
        end

        description "Manage holdings, tags, and simple transaction rules"

        arguments do
          required(:action).value(:string).value(included_in?: ACTIONS).description("Operation to perform: holdings, tags, or rules management")
          optional(:id).value(:string).description("Holding/Tag/Rule ID (required for update/delete operations)")
          optional(:account_id).value(:string).description("Account ID (required for create_holding)")
          optional(:security_id).value(:string).description("Security ID (optional for create_holding)")
          optional(:quantity).filled.description("Holding quantity (optional for create/update_holding)")
          optional(:price).filled.description("Holding price (optional for create/update_holding)")
          optional(:amount).filled.description("Holding amount (optional for create/update_holding)")
          optional(:currency).value(:string).description("Currency code (optional for create/update_holding)")
          optional(:date).value(:string).description("Holding date ISO 8601 (optional for create/update_holding)")
          optional(:name).value(:string).description("Tag/Rule name (required for create_tag, optional for update_rule)")
          optional(:color).value(:string).description("Tag color (optional for create_tag)")
          optional(:transaction_id).value(:string).description("Transaction ID (required for assign_tag/remove_tag)")
          optional(:tag_id).value(:string).description("Tag ID (required for assign_tag/remove_tag)")
        end

        # rubocop:disable Lint/UnusedMethodArgument
        def call(action:, idempotency_key: nil, **args)
          family_id = server_context[:family_id]
          tool_name = self.class.tool_name
          Tools::AuditWrapper.with_audit(tool: tool_name, action: action, family_id: family_id, params: args) do
            Tools::Idempotency.with_idempotency(tool: tool_name, key: idempotency_key.to_s, family_id: family_id) do
              case action
              when "create_holding" then create_holding(args)
              when "update_holding" then update_holding(args)
              when "delete_holding" then delete_holding(args)
              when "create_tag" then create_tag(args)
              when "delete_tag" then delete_tag(args)
              when "assign_tag" then assign_tag(args)
              when "remove_tag" then remove_tag(args)
              when "create_rule" then create_rule(args)
              when "update_rule" then update_rule(args)
              when "delete_rule" then delete_rule(args)
              when "run_rule" then run_rule(args)
              else
                raise ArgumentError, "Unsupported action: #{action}"
              end
            end
          end
        rescue ActiveRecord::RecordNotFound => e
          not_found_error(e.message)
        rescue ActiveRecord::RecordInvalid => e
          validation_error(
            "#{action.gsub('_', ' ').capitalize} failed",
            e.record.errors.messages
          )
        rescue ArgumentError => e
          validation_error(e.message)
        rescue StandardError => e
          logger.error("asset_ops error: #{e.class} #{e.message}")
          logger.error(e.backtrace.join("\n")) if e.backtrace
          internal_error("An unexpected error occurred")
        ensure
          # rubocop:enable Lint/UnusedMethodArgument
        end

        private

        def create_holding(payload)
          family_id = server_context[:family_id]

          # Validate required fields
          unless payload[:account_id]
            raise ArgumentError, "account_id is required"
          end

          # Find account (raises RecordNotFound if not found)
          account = Models::Account.find_for_family!(family_id, payload[:account_id])

          # Create holding
          holding = Models::Holding.new(account_id: account.id)
          assign_if_column(holding, :security_id, payload[:security_id])
          # Coerce numeric fields
          assign_if_column(holding, :qty, coerce_decimal(payload[:quantity], field_name: "quantity")) if payload[:quantity]
          assign_if_column(holding, :currency, payload[:currency])
          assign_if_column(holding, :price, coerce_decimal(payload[:price], field_name: "price")) if payload[:price]
          assign_if_column(holding, :amount, coerce_decimal(payload[:amount], field_name: "amount")) if payload[:amount]

          # Parse date with error handling
          if payload[:date]
            begin
              holding_date = parse_date(payload[:date])
              assign_if_column(holding, :date, holding_date)
            rescue ArgumentError, Date::Error => e
              raise ArgumentError, "Invalid date format: #{e.message}"
            end
          else
            assign_if_column(holding, :date, Date.today)
          end

          holding.save!
          { ok: true, result: { holding: serialize_holding(holding) } }
        end

        def update_holding(payload)
          family_id = server_context[:family_id]
          holding = Models::Holding.find(payload.fetch(:id))
          ensure_family_access!(holding, family_id)

          updates = {}
          updates[:qty] = coerce_decimal(payload[:quantity], field_name: "quantity") if payload.key?(:quantity)
          updates[:price] = coerce_decimal(payload[:price], field_name: "price") if payload.key?(:price)
          updates[:amount] = coerce_decimal(payload[:amount], field_name: "amount") if payload.key?(:amount)
          updates[:currency] = payload[:currency] if payload.key?(:currency)
          updates[:date] = parse_date(payload[:date]) if payload.key?(:date)
          assign_and_save(holding, updates)

          { ok: true, result: { holding: serialize_holding(holding) } }
        end

        def delete_holding(payload)
          family_id = server_context[:family_id]
          holding = Models::Holding.find(payload.fetch(:id))
          ensure_family_access!(holding, family_id)
          resource_id = holding.id
          holding.destroy!
          { ok: true, result: { deleted: true, resource_id: resource_id, resource_type: "holding" } }
        end

        def create_tag(payload)
          family_id = server_context[:family_id]
          tag = Models::Tag.new(family_id: family_id, name: payload.fetch(:name))
          assign_if_column(tag, :color, payload[:color])
          tag.save!
          { ok: true, result: { tag: serialize_tag(tag) } }
        end

        def delete_tag(payload)
          family_id = server_context[:family_id]
          tag = Models::Tag.find(payload.fetch(:id))
          raise ActiveRecord::RecordNotFound unless tag.family_id == family_id
          resource_id = tag.id
          tag.destroy!
          { ok: true, result: { deleted: true, resource_id: resource_id, resource_type: "tag" } }
        end

        def assign_tag(payload)
          family_id = server_context[:family_id]
          transaction = Models::Transaction.find(payload.fetch(:transaction_id))
          ensure_transaction_family!(transaction, family_id)
          tag = Models::Tag.find(payload.fetch(:tag_id))
          raise ActiveRecord::RecordNotFound unless tag.family_id == family_id

          Models::Tagging.create!(tag_id: tag.id, taggable: transaction)
          { ok: true, result: { transaction_id: transaction.id, tag_id: tag.id } }
        end

        def remove_tag(payload)
          family_id = server_context[:family_id]
          transaction = Models::Transaction.find(payload.fetch(:transaction_id))
          ensure_transaction_family!(transaction, family_id)
          tag = Models::Tag.find(payload.fetch(:tag_id))
          raise ActiveRecord::RecordNotFound unless tag.family_id == family_id

          Models::Tagging.where(tag_id: tag.id, taggable: transaction).destroy_all
          { ok: true, result: { removed: true } }
        end

        def create_rule(payload)
          family_id = server_context[:family_id]
          rule = Models::Rule.new(family_id: family_id, name: payload[:name], resource_type: "transaction")
          rule.save!
          { ok: true, result: { rule: serialize_rule(rule) } }
        end

        def update_rule(payload)
          family_id = server_context[:family_id]
          rule = Models::Rule.find(payload.fetch(:id))
          raise ActiveRecord::RecordNotFound unless rule.family_id == family_id

          updates = {}
          updates[:name] = payload[:name] if payload.key?(:name)
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
          rule.apply if rule.respond_to?(:apply)
          { ok: true, result: { applied: true } }
        end

        def ensure_family_access!(holding, family_id)
          raise ActiveRecord::RecordNotFound unless holding.account.family_id == family_id
        end

        def ensure_transaction_family!(transaction, family_id)
          entry = transaction.entry
          raise ActiveRecord::RecordNotFound unless entry&.account&.family_id == family_id
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

        def serialize_holding(holding)
          {
            id: holding.id,
            account_id: holding.account_id,
            security_id: (holding[:security_id] if column?(Models::Holding, :security_id)),
            quantity: (holding[:qty] if column?(Models::Holding, :qty)),
            amount: (holding[:amount] if column?(Models::Holding, :amount)),
            currency: (holding[:currency] if column?(Models::Holding, :currency)),
            date: (holding[:date]&.iso8601 if column?(Models::Holding, :date))
          }.compact
        end

        def serialize_tag(tag)
          {
            id: tag.id,
            name: tag.name,
            color: (tag[:color] if column?(Models::Tag, :color))
          }.compact
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
