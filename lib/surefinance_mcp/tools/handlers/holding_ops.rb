# frozen_string_literal: true

require "date"

module SurefinanceMCP
  module Tools
    module Handlers
      # Holdings tool: manage holdings, trades, valuations, tags
      class HoldingOps < FastMcp::Tool
        include SurefinanceMCP::Tools::BaseTool

        ACTIONS = %w[
          create_holding update_holding delete_holding
          record_trade record_valuation
          create_tag delete_tag assign_tag remove_tag
        ].freeze

        def self.tool_name
          "asset_ops"
        end

        description "Manage holdings, trades, valuations, and tags (family scoped)"

        arguments do
          required(:action).value(:string).value(included_in?: ACTIONS)
          required(:payload).value(:hash)
          optional(:idempotency_key).value(:string)
        end

        # rubocop:disable Lint/UnusedMethodArgument
        def call(action:, payload:, idempotency_key: nil)
          family_id = server_context[:family_id]
          tool_name = self.class.tool_name
          Tools::AuditWrapper.with_audit(tool: tool_name, action: action, family_id: family_id, params: payload) do
            Tools::Idempotency.with_idempotency(tool: tool_name, key: idempotency_key.to_s, family_id: family_id) do
              case action
              when "create_holding" then create_holding(payload)
              when "update_holding" then update_holding(payload)
              when "delete_holding" then delete_holding(payload)
              when "record_trade" then record_trade(payload)
              when "record_valuation" then record_valuation(payload)
              when "create_tag" then create_tag(payload)
              when "delete_tag" then delete_tag(payload)
              when "assign_tag" then assign_tag(payload)
              when "remove_tag" then remove_tag(payload)
              else
                raise ArgumentError, "Unsupported action: #{action}"
              end
            end
          end
        rescue ActiveRecord::RecordNotFound => e
          { ok: false, error: { type: "not_found", code: "asset.not_found", message: e.message } }
        rescue ArgumentError => e
          { ok: false, error: { type: "validation_error", code: "asset.invalid", message: e.message } }
        rescue StandardError => e
          logger.error("asset_ops error: #{e.class} #{e.message}")
          { ok: false, error: { type: "internal", code: "asset.internal", message: "Internal error" } }
        ensure
          # rubocop:enable Lint/UnusedMethodArgument
        end

        private

        def create_holding(payload)
          family_id = server_context[:family_id]
          account = Models::Account.find_for_family!(family_id, payload.fetch(:account_id))
          holding = Models::Holding.new(
            account_id: account.id
          )
          assign_if_column(holding, :security_id, payload[:security_id])
          assign_if_column(holding, :qty, payload[:quantity])
          assign_if_column(holding, :currency, payload[:currency])
          assign_if_column(holding, :price, payload[:price])
          assign_if_column(holding, :amount, payload[:amount])
          assign_if_column(holding, :date, parse_date(payload[:date]) || Date.today)
          holding.save!
          { ok: true, result: { holding: serialize_holding(holding) } }
        end

        def update_holding(payload)
          family_id = server_context[:family_id]
          holding = Models::Holding.find(payload.fetch(:id))
          ensure_family_access!(holding, family_id)

          updates = {}
          updates[:qty] = payload[:quantity] if payload.key?(:quantity)
          updates[:price] = payload[:price] if payload.key?(:price)
          updates[:amount] = payload[:amount] if payload.key?(:amount)
          updates[:currency] = payload[:currency] if payload.key?(:currency)
          updates[:date] = parse_date(payload[:date]) if payload.key?(:date)

          assign_and_save(holding, updates)
          { ok: true, result: { holding: serialize_holding(holding) } }
        end

        def delete_holding(payload)
          family_id = server_context[:family_id]
          holding = Models::Holding.find(payload.fetch(:id))
          ensure_family_access!(holding, family_id)
          holding.destroy!
          { ok: true, result: { deleted: true } }
        end

        def record_trade(payload)
          family_id = server_context[:family_id]
          account = Models::Account.find_for_family!(family_id, payload.fetch(:account_id))

          trade = Models::Holding.where(account_id: account.id) # Placeholder
          raise ArgumentError, "Trades not supported in this lightweight model" unless defined?(::Trade)
          # If Trade model exists, create entry similarly to transaction

          raise ArgumentError, "Trade recording not implemented"
        end

        def record_valuation(payload)
          raise ArgumentError, "Valuations not implemented in this lightweight model"
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
          tag.destroy!
          { ok: true, result: { deleted: true } }
        end

        def assign_tag(payload)
          family_id = server_context[:family_id]
          transaction = Models::Transaction.find(payload.fetch(:transaction_id))
          entry = transaction.entry || transaction.entries.first
          raise ActiveRecord::RecordNotFound unless entry&.account&.family_id == family_id

          tag = Models::Tag.find(payload.fetch(:tag_id))
          raise ActiveRecord::RecordNotFound unless tag.family_id == family_id

          Models::Tagging.create!(tag_id: tag.id, taggable: transaction)
          { ok: true, result: { transaction_id: transaction.id, tag_id: tag.id } }
        end

        def remove_tag(payload)
          family_id = server_context[:family_id]
          transaction = Models::Transaction.find(payload.fetch(:transaction_id))
          entry = transaction.entry || transaction.entries.first
          raise ActiveRecord::RecordNotFound unless entry&.account&.family_id == family_id

          tag = Models::Tag.find(payload.fetch(:tag_id))
          raise ActiveRecord::RecordNotFound unless tag.family_id == family_id

          Models::Tagging.where(tag_id: tag.id, taggable: transaction).destroy_all
          { ok: true, result: { removed: true } }
        end

        def ensure_family_access!(holding, family_id)
          raise ActiveRecord::RecordNotFound unless holding.account.family_id == family_id
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
            security_id: holding.respond_to?(:security_id) ? holding.security_id : nil,
            quantity: holding.respond_to?(:qty) ? holding.qty : nil,
            amount: holding.respond_to?(:amount) ? holding.amount : nil,
            currency: holding.respond_to?(:currency) ? holding.currency : nil,
            date: holding.respond_to?(:date) ? holding.date&.iso8601 : nil
          }.compact
        end

        def serialize_tag(tag)
          {
            id: tag.id,
            name: tag.name,
            color: (tag[:color] if column?(Models::Tag, :color))
          }.compact
        end
      end
    end
  end
end
