# frozen_string_literal: true

require "date"

module SurefinanceMCP
  module Tools
    module Handlers
      # Transaction management tool: create | update | delete | split | categorize | bulk_categorize | set_cleared
      class TransactionOps < FastMcp::Tool
        include SurefinanceMCP::Tools::BaseTool

        ACTIONS = %w[create update delete split categorize bulk_categorize set_cleared].freeze
        BULK_LIMIT = 500

        def self.tool_name
          "transaction_ops"
        end

        description "Manage transactions: CRUD, splits, categorization, clearing (family scoped)"

        arguments do
          required(:action).value(:string).value(included_in?: ACTIONS).description("Operation to perform: create, update, delete, split, categorize, bulk_categorize, set_cleared")
          optional(:id).value(:string).description("Transaction ID (required for update/delete/split/categorize/set_cleared)")
          optional(:account_id).value(:string).description("Account ID (required for create)")
          optional(:amount).filled.description("Transaction amount (required for create, optional for update)")
          optional(:date).value(:string).description("Transaction date ISO 8601 (optional for create/update)")
          optional(:category_id).value(:string).description("Category ID (optional for create/update/categorize/bulk_categorize)")
          optional(:memo).value(:string).description("Transaction memo (optional for create/update)")
          optional(:merchant).value(:string).description("Merchant name (optional for create/update)")
          optional(:description).value(:string).description("Transaction description (optional for create/update)")
          optional(:splits).array(:hash) do
            optional(:amount).filled
            optional(:category_id).value(:string)
            optional(:memo).value(:string)
            optional(:date).value(:string)
            optional(:description).value(:string)
          end.description("Array of split objects (required for split action)")
          optional(:ids).array(:string).description("Array of transaction ID strings")
          optional(:cleared).value(:bool).description("Cleared status (required for set_cleared)")
        end

        # rubocop:disable Lint/UnusedMethodArgument
        def call(action:, idempotency_key: nil, **args)
          family_id = server_context[:family_id]
          tool_name = self.class.tool_name
          Tools::AuditWrapper.with_audit(tool: tool_name, action: action, family_id: family_id, params: args) do
            Tools::Idempotency.with_idempotency(tool: tool_name, key: idempotency_key.to_s, family_id: family_id) do
              case action
              when "create" then create_transaction(args)
              when "update" then update_transaction(args)
              when "delete" then delete_transaction(args)
              when "split" then split_transaction(args)
              when "categorize" then categorize_transaction(args)
              when "bulk_categorize" then bulk_categorize(args)
              when "set_cleared" then set_cleared(args)
              else
                raise ArgumentError, "Unsupported action: #{action}"
              end
            end
          end
        rescue ActiveRecord::RecordNotFound => e
          { ok: false, error: { type: "not_found", code: "transaction.not_found", message: e.message } }
        rescue ActiveRecord::RecordInvalid => e
          { ok: false, error: { type: "validation_error", code: "transaction.invalid", message: e.record.errors.full_messages.join(", ") } }
        rescue ArgumentError => e
          { ok: false, error: { type: "validation_error", code: "transaction.invalid", message: e.message } }
        rescue StandardError => e
          logger.error("transaction_ops error: #{e.class} #{e.message}")
          { ok: false, error: { type: "internal", code: "transaction.internal", message: "Internal error" } }
        ensure
          # rubocop:enable Lint/UnusedMethodArgument
        end

        private

        def create_transaction(payload)
          family_id = server_context[:family_id]

          # Required fields validation
          account_id = payload.fetch(:account_id) { raise ArgumentError, "account_id is required" }
          raw_amount = payload.fetch(:amount) { raise ArgumentError, "amount is required" }
          amount = coerce_decimal(raw_amount, field_name: "amount")

          account = Models::Account.find_for_family!(family_id, account_id)

          # Required Entry fields with defaults
          entry_date = payload[:date] ? Date.parse(payload[:date].to_s) : Date.today
          entry_name = payload[:description] || "Transaction" # Entry.name is required
          entry_currency = account.currency # Use account's currency

          ActiveRecord::Base.transaction do
            transaction_record = Models::Transaction.new
            assign_if_column(transaction_record, :category_id, payload[:category_id]) if payload[:category_id]
            assign_if_column(transaction_record, :memo, payload[:memo]) if payload.key?(:memo)
            assign_if_column(transaction_record, :merchant_name, payload[:merchant]) if payload.key?(:merchant)
            assign_if_column(transaction_record, :amount_cents, to_cents(amount)) if column?(Models::Transaction, :amount_cents)
            assign_if_column(transaction_record, :amount, amount) if column?(Models::Transaction, :amount)
            transaction_record.save!

            entry = Models::Entry.new(
              account_id: account.id,
              entryable: transaction_record,
              date: entry_date,
              amount: amount,
              name: entry_name,
              currency: entry_currency
            )
            entry.save!

            { ok: true, result: { transaction: serialize_transaction(transaction_record, entry: entry) } }
          end
        end

        def update_transaction(payload)
          family_id = server_context[:family_id]
          id = payload.fetch(:id)
          transaction_record = Models::Transaction.find(id)
          ensure_family_access!(transaction_record, family_id)

          updates = {}
          entry_updates = {}

          if payload.key?(:category_id)
            category = Models::Category.find_for_family!(family_id, payload[:category_id])
            updates[:category_id] = category.id
          end

          updates[:memo] = payload[:memo] if payload.key?(:memo) && column?(Models::Transaction, :memo)
          updates[:merchant_name] = payload[:merchant] if payload.key?(:merchant) && column?(Models::Transaction, :merchant_name)
          if payload.key?(:amount)
            amount = coerce_decimal(payload[:amount], field_name: "amount")
            updates[:amount] = amount if column?(Models::Transaction, :amount)
            updates[:amount_cents] = to_cents(amount) if column?(Models::Transaction, :amount_cents)
            entry_updates[:amount] = amount
          end
          if payload.key?(:date)
            entry_updates[:date] = Date.parse(payload[:date].to_s)
          end
          entry_updates[:name] = payload[:description] if payload.key?(:description)

          ActiveRecord::Base.transaction do
            assign_and_save(transaction_record, updates)
            entry = transaction_record.entry
            if entry
              entry.assign_attributes(entry_updates)
              entry.save!
            end
          end

          { ok: true, result: { transaction: serialize_transaction(transaction_record) } }
        end

        def delete_transaction(payload)
          family_id = server_context[:family_id]
          id = payload.fetch(:id)
          transaction_record = Models::Transaction.find(id)
          ensure_family_access!(transaction_record, family_id)

          ActiveRecord::Base.transaction do
            entry = transaction_record.entry
            entry.destroy! if entry
            transaction_record.destroy!
          end

          { ok: true, result: { deleted: true, resource_id: id, resource_type: "transaction" } }
        end

        def split_transaction(payload)
          family_id = server_context[:family_id]
          id = payload.fetch(:id)
          splits = payload.fetch(:splits)
          raise ArgumentError, "splits must be an array" unless splits.is_a?(Array) && splits.any?

          transaction_record = Models::Transaction.find(id)
          ensure_family_access!(transaction_record, family_id)

          parent_entry = transaction_record.entry
          raise ArgumentError, "Transaction has no entry to split" unless parent_entry

          parent_amount = parent_entry.amount.to_f
          # Coerce split amounts to BigDecimal and calculate total
          coerced_splits = splits.map do |s|
            s.merge(coerced_amount: coerce_decimal(s.fetch(:amount), field_name: "split amount"))
          end
          total_splits = coerced_splits.sum { |s| s[:coerced_amount].to_f }
          unless (parent_amount - total_splits).abs < 0.01
            raise ArgumentError, "Split amounts must sum to parent amount"
          end

          ActiveRecord::Base.transaction do
            parent_entry.update!(amount: parent_amount)
            coerced_splits.each do |split|
              split_amount = split[:coerced_amount]
              child = Models::Transaction.new
              assign_if_column(child, :category_id, split[:category_id]) if split[:category_id]
              assign_if_column(child, :memo, split[:memo]) if split.key?(:memo)
              assign_if_column(child, :amount, split_amount) if column?(Models::Transaction, :amount)
              assign_if_column(child, :amount_cents, to_cents(split_amount)) if column?(Models::Transaction, :amount_cents)
              child.save!

              Models::Entry.create!(
                account_id: parent_entry.account_id,
                entryable: child,
                date: split[:date] ? Date.parse(split[:date].to_s) : parent_entry.date,
                amount: split_amount,
                name: split[:description] || parent_entry.name,
                currency: parent_entry.currency
              )
            end
          end

          { ok: true, result: { parent: serialize_transaction(transaction_record), splits: serialize_transaction_children(transaction_record) } }
        end

        def categorize_transaction(payload)
          family_id = server_context[:family_id]
          id = payload.fetch(:id)
          category_id = payload.fetch(:category_id)

          transaction_record = Models::Transaction.find(id)
          ensure_family_access!(transaction_record, family_id)
          category = Models::Category.find_for_family!(family_id, category_id)

          assign_and_save(transaction_record, { category_id: category.id })

          { ok: true, result: { transaction: serialize_transaction(transaction_record) } }
        end

        def bulk_categorize(payload)
          family_id = server_context[:family_id]
          ids = payload.fetch(:ids)
          raise ArgumentError, "ids must be array" unless ids.is_a?(Array)
          raise ArgumentError, "ids limit exceeded" if ids.size > BULK_LIMIT

          category = Models::Category.find_for_family!(family_id, payload.fetch(:category_id))

          results = ids.map do |id|
            begin
              transaction_record = Models::Transaction.find(id)
              ensure_family_access!(transaction_record, family_id)
              assign_and_save(transaction_record, { category_id: category.id })
              { id: id, ok: true }
            rescue StandardError => e
              { id: id, ok: false, error: e.message }
            end
          end

          success_count = results.count { |r| r[:ok] }
          error_count = results.size - success_count

          { ok: true, result: { results: results, success_count: success_count, error_count: error_count } }
        end

        def set_cleared(payload)
          family_id = server_context[:family_id]
          id = payload.fetch(:id)
          cleared = payload.fetch(:cleared)

          transaction_record = Models::Transaction.find(id)
          ensure_family_access!(transaction_record, family_id)

          assign_and_save(transaction_record, { cleared: cleared }) if column?(Models::Transaction, :cleared)

          { ok: true, result: { transaction: serialize_transaction(transaction_record) } }
        end

        def ensure_family_access!(transaction_record, family_id)
          entry = transaction_record.entry
          raise ActiveRecord::RecordNotFound, "Transaction has no associated entry" unless entry
          raise ActiveRecord::RecordNotFound, "Transaction not in family" unless entry.account.family_id == family_id
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

        def to_cents(amount)
          (amount.to_f * 100).round
        end

        def serialize_transaction(record, entry: nil)
          entry ||= record.entry
          {
            id: record.id,
            account_id: entry&.account_id,
            date: entry&.date&.iso8601,
            amount: entry&.amount,
            description: entry&.name,
            category_id: record.respond_to?(:category_id) ? record.category_id : nil
          }.compact
        end

        def serialize_transaction_children(parent)
          parent_entry = parent.entry
          return [] unless parent_entry&.transfer_id

          # Find all entries in the same transfer (splits)
          Models::Entry.where(transfer_id: parent_entry.transfer_id)
                       .includes(:entryable)
                       .map do |entry|
            entryable = entry.entryable
            next unless entryable.is_a?(Models::Transaction) && entryable != parent

            serialize_transaction(entryable, entry: entry)
          end.compact
        end
      end
    end
  end
end
