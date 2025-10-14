# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    module Handlers
      # Category management tool with compact action switch
      # Actions: create | update | move | delete | merge
      class CategoryOps < FastMcp::Tool
        include SurefinanceMCP::Tools::BaseTool

        ACTIONS = %w[create update move delete merge].freeze

        def self.tool_name
          "category_ops"
        end

        description "Manage categories: create, update, move, delete, merge (family scoped)"

        arguments do
          required(:action).value(:string).value(included_in?: ACTIONS).description("Operation to perform: create, update, move, delete, merge")
          optional(:id).value(:string).description("Category ID (required for update/move/delete)")
          optional(:name).value(:string).description("Category name (required for create)")
          optional(:classification).value(:string).description("Classification: income or expense (required for create)")
          optional(:parent_id).value(:string).description("Parent category ID (optional for create/move)")
          optional(:lucide_icon).value(:string).description("Lucide icon name (optional for create/update)")
          optional(:color).value(:string).description("Hex color code (optional for create/update root categories)")
          optional(:new_parent_id).value(:string).description("New parent ID (required for move)")
          optional(:replacement_category_id).value(:string).description("Replacement category ID (optional for delete)")
          optional(:source_id).value(:string).description("Source category ID (required for merge)")
          optional(:target_id).value(:string).description("Target category ID (required for merge)")
        end

        # rubocop:disable Lint/UnusedMethodArgument
        def call(action:, idempotency_key: nil, **args)
          family_id = server_context[:family_id]
          tool_name = self.class.tool_name
          Tools::AuditWrapper.with_audit(tool: tool_name, action: action, family_id: family_id, params: args) do
            Tools::Idempotency.with_idempotency(tool: tool_name, key: idempotency_key.to_s, family_id: family_id) do
              case action
              when "create" then create_category(args)
              when "update" then update_category(args)
              when "move"   then move_category(args)
              when "delete" then delete_category(args)
              when "merge"  then merge_categories(args)
              else
                raise ArgumentError, "Unsupported action: #{action}"
              end
            end
          end
        rescue ActiveRecord::RecordNotFound => e
          { ok: false, error: { type: "not_found", code: "category.not_found", message: e.message } }
        rescue ActiveRecord::RecordInvalid => e
          { ok: false, error: { type: "validation_error", code: "category.invalid", message: e.record.errors.full_messages.join(", ") } }
        rescue ArgumentError => e
          { ok: false, error: { type: "validation_error", code: "category.invalid", message: e.message } }
        rescue StandardError => e
          logger.error("category_ops error: #{e.class} #{e.message}")
          { ok: false, error: { type: "internal", code: "category.internal", message: "Internal error" } }
        ensure
          # rubocop:enable Lint/UnusedMethodArgument
        end

        private

        def create_category(payload)
          family_id = server_context[:family_id]
          name = payload.fetch(:name)
          classification = payload.fetch(:classification)
          parent_id = payload[:parent_id]
          lucide_icon = payload[:lucide_icon]
          color = payload[:color]

          ensure_inclusion!(classification, %w[income expense], "classification must be 'income' or 'expense'")
          ensure_present!(lucide_icon, "lucide_icon is required") if column?(Models::Category, :lucide_icon)

          parent = nil
          if parent_id
            parent = Models::Category.find_for_family!(family_id, parent_id)
            # Two-level hierarchy: parent must be a root (no parent)
            raise ArgumentError, "Two-level hierarchy only" if parent.parent_id
            # Child classification must match parent
            if parent.respond_to?(:classification) && parent.classification && parent.classification != classification
              raise ArgumentError, "Child classification must match parent"
            end
            # Child inherits parent's color
            color = parent.respond_to?(:color) ? parent.color : color
          else
            # Root categories must provide color when column exists
            ensure_present!(color, "color is required for root categories") if column?(Models::Category, :color)
          end

          ensure_unique_name!(family_id, name)

          record = Models::Category.new(
            name: name,
            family_id: family_id,
            parent_id: parent&.id,
            lucide_icon: lucide_icon
          )
          # Only set known optional attributes if columns exist
          assign_if_column(record, :classification, classification)
          assign_if_column(record, :color, color)

          record.save!
          { ok: true, result: { category: serialize_category(record) } }
        end

        def update_category(payload)
          family_id = server_context[:family_id]
          id = payload.fetch(:id)
          record = Models::Category.find_for_family!(family_id, id)

          permitted = {}
          if payload.key?(:name)
            ensure_unique_name!(family_id, payload[:name], exclude_id: record.id)
            permitted[:name] = payload[:name]
          end

          if payload.key?(:lucide_icon)
            ensure_present!(payload[:lucide_icon], "lucide_icon is required")
            permitted[:lucide_icon] = payload[:lucide_icon]
          elsif record.respond_to?(:lucide_icon) && record.lucide_icon.to_s.strip.empty?
            raise ArgumentError, "lucide_icon is required"
          end

          if payload.key?(:color)
            # Only root categories can set color directly
            if record.parent_id
              raise ArgumentError, "Only root categories can set color; children inherit parent color"
            end
            ensure_present!(payload[:color], "color is required for root categories")
            permitted[:color] = payload[:color]
          end

          # Disallow classification changes by default (policy)
          if payload.key?(:classification)
            raise ArgumentError, "Reclassification not supported"
          end

          # Persist changes
          assign_and_save(record, permitted)

          # Propagate color to children if root color changed
          if permitted.key?(:color)
            if column?(Models::Category, :color)
              record.children.update_all(color: permitted[:color])
            end
          end

          { ok: true, result: { category: serialize_category(record) } }
        end

        def move_category(payload)
          family_id = server_context[:family_id]
          id = payload.fetch(:id)
          new_parent_id = payload.fetch(:new_parent_id)

          record = Models::Category.find_for_family!(family_id, id)

          new_parent = nil
          if new_parent_id
            new_parent = Models::Category.find_for_family!(family_id, new_parent_id)
            # Two-level hierarchy: new parent must be root
            raise ArgumentError, "Two-level hierarchy only" if new_parent.parent_id
            # Classification match (if column available)
            if column?(Models::Category, :classification)
              if new_parent.classification && record.classification && new_parent.classification != record.classification
                raise ArgumentError, "Classification mismatch between child and new parent"
              end
            end
          end

          ActiveRecord::Base.transaction do
            updates = { parent_id: new_parent&.id }
            if new_parent && column?(Models::Category, :color)
              updates[:color] = new_parent.color
            end
            assign_and_save(record, updates)

            # Ensure children inherit moved color if applicable
            if new_parent && column?(Models::Category, :color)
              record.children.update_all(color: record.color)
            end
          end

          { ok: true, result: { category: serialize_category(record) } }
        end

        def delete_category(payload)
          family_id = server_context[:family_id]
          id = payload.fetch(:id)
          replacement_id = payload[:replacement_category_id]

          record = Models::Category.find_for_family!(family_id, id)
          replacement = nil
          moved_txns = 0

          ActiveRecord::Base.transaction do
            if replacement_id
              replacement = Models::Category.find_for_family!(family_id, replacement_id)
              # Classification compatibility if column available
              if column?(Models::Category, :classification)
                if record.classification && replacement.classification && record.classification != replacement.classification
                  raise ArgumentError, "Replacement classification mismatch"
                end
              end

              # Move transactions to replacement
              if column?(Models::Transaction, :category_id)
                moved_txns = Models::Transaction.where(category_id: record.id).update_all(category_id: replacement.id)
              end

              # Rewire budget_categories; handle duplicates by deleting source duplicates
              if defined?(Models::BudgetCategory)
                Models::BudgetCategory.where(category_id: record.id).find_each do |bc|
                  existing = Models::BudgetCategory.where(budget_id: bc.budget_id, category_id: replacement.id).first
                  if existing
                    bc.destroy!
                  else
                    bc.update!(category_id: replacement.id)
                  end
                end
              end
            else
              # No replacement provided; ensure no transactions remain
              if Models::Transaction.where(category_id: record.id).exists?
                raise ArgumentError, "Cannot delete category with transactions without a replacement"
              end
            end

            record.destroy!
          end

          { ok: true, result: { destroyed: true, reassigned_count: moved_txns } }
        end

        def merge_categories(payload)
          family_id = server_context[:family_id]
          source_id = payload.fetch(:source_id)
          target_id = payload.fetch(:target_id)
          raise ArgumentError, "source and target must be different" if source_id == target_id

          source = Models::Category.find_for_family!(family_id, source_id)
          target = Models::Category.find_for_family!(family_id, target_id)

          if column?(Models::Category, :classification)
            if source.classification && target.classification && source.classification != target.classification
              raise ArgumentError, "Classification mismatch between source and target"
            end
          end

          moved_txns = 0
          moved_bcs = 0

          ActiveRecord::Base.transaction do
            # Move transactions
            if column?(Models::Transaction, :category_id)
              moved_txns = Models::Transaction.where(category_id: source.id).update_all(category_id: target.id)
            end

            # Rewire budget_categories
            if defined?(Models::BudgetCategory)
              Models::BudgetCategory.where(category_id: source.id).find_each do |bc|
                existing = Models::BudgetCategory.where(budget_id: bc.budget_id, category_id: target.id).first
                if existing
                  bc.destroy!
                else
                  bc.update!(category_id: target.id)
                  moved_bcs += 1
                end
              end
            end

            source.destroy!
          end

          { ok: true, result: { merged: true, moved_transactions: moved_txns, moved_budget_categories: moved_bcs } }
        end

        # Helpers
        def assign_if_column(record, attr, value)
          return unless column?(record.class, attr)
          record.send(:"#{attr}=", value)
        end

        def assign_and_save(record, attrs)
          attrs.each do |k, v|
            assign_if_column(record, k, v)
          end
          record.save!
        end

        def ensure_unique_name!(family_id, name, exclude_id: nil)
          scope = Models::Category.for_family(family_id).where(name: name)
          scope = scope.where.not(id: exclude_id) if exclude_id
          raise ArgumentError, "Category name must be unique within family" if scope.exists?
        end

        def ensure_inclusion!(value, allowed, message)
          raise ArgumentError, message unless allowed.include?(value)
        end

        def ensure_present!(value, message)
          raise ArgumentError, message if value.nil? || value.to_s.strip.empty?
        end

        def column?(ar_class, attr)
          ar_class.column_names.include?(attr.to_s)
        end

        def serialize_category(record)
          {
            id: record.id,
            name: record.name,
            parent_id: record.parent_id,
            color: (record.color if record.respond_to?(:color)),
            classification: (record.classification if record.respond_to?(:classification)),
            lucide_icon: (record.lucide_icon if record.respond_to?(:lucide_icon))
          }.compact
        end
      end
    end
  end
end
