# frozen_string_literal: true

require "date"

module SurefinanceMCP
  module Tools
    module Handlers
      # Budget management tool: create | update | delete | assign_category | remove_category | progress
      class BudgetOps < FastMcp::Tool
        include SurefinanceMCP::Tools::BaseTool

        ACTIONS = %w[create update delete assign_category remove_category progress].freeze

        def self.tool_name
          "budget_ops"
        end

        description "Manage budgets: create, update, delete, assign/remove categories, progress (family scoped)"

        arguments do
          required(:action).value(:string).value(included_in?: ACTIONS).description("Operation to perform: create, update, delete, assign_category, remove_category, progress")
          optional(:budget_id).value(:string).description("Budget ID (required for update/delete/progress/assign_category/remove_category)")
          optional(:start_date).value(:string).description("Start date ISO 8601 (optional for create)")
          optional(:month).value(:string).description("Month in format 'Oct-2025' (optional for create)")
          optional(:budgeted_spending).filled.description("Budgeted spending amount (optional for update/assign_category)")
          optional(:expected_income).filled.description("Expected income amount (optional for update)")
          optional(:category_id).value(:string).description("Category ID (required for assign_category/remove_category)")
        end

        # rubocop:disable Lint/UnusedMethodArgument
        def call(action:, idempotency_key: nil, **args)
          family_id = server_context[:family_id]
          tool_name = self.class.tool_name
          Tools::AuditWrapper.with_audit(tool: tool_name, action: action, family_id: family_id, params: args) do
            Tools::Idempotency.with_idempotency(tool: tool_name, key: idempotency_key.to_s, family_id: family_id) do
              case action
              when "create" then create_budget(args)
              when "update" then update_budget(args)
              when "delete" then delete_budget(args)
              when "assign_category" then assign_category(args)
              when "remove_category" then remove_category(args)
              when "progress" then budget_progress(args)
              else
                raise ArgumentError, "Unsupported action: #{action}"
              end
            end
          end
        rescue ActiveRecord::RecordNotFound => e
          not_found_error(e.message)
        rescue ActiveRecord::RecordInvalid => e
          validation_error(
            "Budget validation failed",
            e.record.errors.messages
          )
        rescue ArgumentError => e
          validation_error(e.message)
        rescue StandardError => e
          logger.error("budget_ops error: #{e.class} #{e.message}")
          logger.error(e.backtrace.join("\n")) if e.backtrace
          internal_error("An unexpected error occurred")
        ensure
          # rubocop:enable Lint/UnusedMethodArgument
        end

        private

        # CREATE
        def create_budget(payload)
          family = Models::Family.find(server_context[:family_id])
          start_date = parse_start_date(payload)

          budget = Models::Budget.for_family(family.id).where(start_date: start_date.beginning_of_month, end_date: start_date.end_of_month).first
          existed = budget.present?

          unless budget
            budget = Models::Budget.new(
              family_id: family.id,
              start_date: start_date.beginning_of_month,
              end_date: start_date.end_of_month
            )
            assign_if_column(budget, :currency, family.currency) if family.respond_to?(:currency)
            budget.save!

            # Sync expense categories into budget_categories
            sync_budget_categories(budget, family)
          end

          result = { budget: serialize_budget(budget) }
          result[:existed] = true if existed
          { ok: true, result: result }
        end

        # UPDATE
        def update_budget(payload)
          family_id = server_context[:family_id]
          budget_id = payload.fetch(:budget_id)
          budget = Models::Budget.find_for_family!(family_id, budget_id)

          updates = {}
          if payload.key?(:budgeted_spending)
            budgeted_spending = coerce_decimal(payload[:budgeted_spending], field_name: "budgeted_spending")
            ensure_non_negative!(budgeted_spending, "budgeted_spending must be non-negative")
            updates[:budgeted_spending] = budgeted_spending
          end
          if payload.key?(:expected_income)
            expected_income = coerce_decimal(payload[:expected_income], field_name: "expected_income")
            ensure_non_negative!(expected_income, "expected_income must be non-negative")
            updates[:expected_income] = expected_income
          end

          assign_and_save(budget, updates)
          { ok: true, result: { budget: serialize_budget(budget) } }
        end

        # DELETE
        def delete_budget(payload)
          family_id = server_context[:family_id]
          budget_id = payload.fetch(:budget_id)
          budget = Models::Budget.find_for_family!(family_id, budget_id)
          resource_id = budget.id
          budget.destroy!
          { ok: true, result: { deleted: true, resource_id: resource_id, resource_type: "budget" } }
        end

        # ASSIGN CATEGORY
        def assign_category(payload)
          family_id = server_context[:family_id]
          budget_id = payload.fetch(:budget_id)
          category_id = payload.fetch(:category_id)

          # Coerce budgeted_spending if present
          budgeted_spending = if payload[:budgeted_spending]
                                coerce_decimal(payload[:budgeted_spending], field_name: "budgeted_spending")
                              end

          budget = Models::Budget.find_for_family!(family_id, budget_id)
          category = Models::Category.find_for_family!(family_id, category_id)

          bc = Models::BudgetCategory.where(budget_id: budget.id, category_id: category.id).first
          unless bc
            bc = Models::BudgetCategory.new(budget_id: budget.id, category_id: category.id)
            if budgeted_spending
              assign_if_column(bc, :budgeted_spending, budgeted_spending)
            end
            # set currency for budget category when present
            if column?(Models::BudgetCategory, :currency) && budget.respond_to?(:family) && budget.family.respond_to?(:currency)
              assign_if_column(bc, :currency, budget.family.currency)
            end
            bc.save!
          else
            if budgeted_spending
              assign_and_save(bc, { budgeted_spending: budgeted_spending })
            end
          end

          { ok: true, result: { budget_category: serialize_budget_category(bc) } }
        end

        # REMOVE CATEGORY
        def remove_category(payload)
          family_id = server_context[:family_id]
          budget_id = payload.fetch(:budget_id)
          category_id = payload.fetch(:category_id)

          budget = Models::Budget.find_for_family!(family_id, budget_id)
          bc = Models::BudgetCategory.where(budget_id: budget.id, category_id: category_id).first
          raise ActiveRecord::RecordNotFound, "BudgetCategory not found" unless bc

          resource_id = bc.id
          bc.destroy!
          { ok: true, result: { removed: true, resource_id: resource_id, resource_type: "budget_category" } }
        end

        # PROGRESS
        def budget_progress(payload)
          family_id = server_context[:family_id]
          budget_id = payload.fetch(:budget_id)
          budget = Models::Budget.find_for_family!(family_id, budget_id)

          # Use stored columns when available; compute percent if both values present
          totals = {
            budgeted_spending: (budget[:budgeted_spending] if column?(Models::Budget, :budgeted_spending)),
            expected_income: (budget[:expected_income] if column?(Models::Budget, :expected_income)),
            actual_spending: (budget[:actual_spending] if column?(Models::Budget, :actual_spending)),
            actual_income: (budget[:actual_income] if column?(Models::Budget, :actual_income))
          }.compact

          overall_percent = nil
          if totals[:budgeted_spending].to_f > 0 && totals[:actual_spending]
            overall_percent = (totals[:actual_spending].to_f / totals[:budgeted_spending].to_f) * 100.0
          end

          per_category = Models::BudgetCategory.where(budget_id: budget.id).includes(:category).map do |bc|
            h = serialize_budget_category(bc)
            if column?(Models::BudgetCategory, :budgeted_spending) && column?(Models::BudgetCategory, :actual_spending)
              if h[:budgeted_spending].to_f > 0 && h[:actual_spending]
                h[:percent_spent] = (h[:actual_spending].to_f / h[:budgeted_spending].to_f) * 100.0
              end
            end
            h
          end

          { ok: true, result: { overall_percent: overall_percent, totals: totals, per_category: per_category } }
        end

        # Helpers
        def parse_start_date(payload)
          if payload[:start_date]
            begin
              Date.parse(payload[:start_date].to_s)
            rescue ArgumentError, Date::Error => e
              raise ArgumentError, "Invalid start_date format: #{e.message}"
            end
          elsif payload[:month]
            # month expected in format like "Oct-2025" (Budget::PARAM_DATE_FORMAT)
            month_str = payload[:month].to_s

            # Validate format before parsing
            unless month_str =~ /^[A-Z][a-z]{2}-\d{4}$/
              raise ArgumentError, "Invalid month format. Expected format: 'Oct-2025', got: '#{month_str}'"
            end

            begin
              Date.strptime(month_str, "%b-%Y")
            rescue ArgumentError, Date::Error => e
              raise ArgumentError, "Invalid month value: #{e.message}"
            end
          else
            raise ArgumentError, "start_date or month is required"
          end
        end

        def ensure_non_negative!(value, message)
          raise ArgumentError, message if value && value.to_f < 0
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

        def sync_budget_categories(budget, family)
          # expense categories only
          scope = Models::Category.for_family(family.id)
          scope = scope.where(classification: "expense") if column?(Models::Category, :classification)

          current_ids = scope.pluck(:id).to_set
          existing_ids = Models::BudgetCategory.where(budget_id: budget.id).pluck(:category_id).to_set

          (current_ids - existing_ids).each do |cid|
            Models::BudgetCategory.create!(budget_id: budget.id, category_id: cid)
          end

          (existing_ids - current_ids).each do |cid|
            Models::BudgetCategory.where(budget_id: budget.id, category_id: cid).delete_all
          end
        end

        def serialize_budget(budget)
          {
            id: budget.id,
            start_date: budget.start_date&.iso8601,
            end_date: budget.end_date&.iso8601,
            period_type: (budget.respond_to?(:period_type) ? budget.period_type : nil),
            budgeted_spending: (budget[:budgeted_spending] if column?(Models::Budget, :budgeted_spending)),
            expected_income: (budget[:expected_income] if column?(Models::Budget, :expected_income)),
            currency: (budget[:currency] if column?(Models::Budget, :currency))
          }.compact
        end

        def serialize_budget_category(bc)
          {
            id: bc.id,
            budget_id: bc.budget_id,
            category_id: bc.category_id,
            budgeted_spending: (bc[:budgeted_spending] if column?(Models::BudgetCategory, :budgeted_spending)),
            actual_spending: (bc[:actual_spending] if column?(Models::BudgetCategory, :actual_spending))
          }.compact
        end
      end
    end
  end
end
