# frozen_string_literal: true

require "spec_helper"

RSpec.describe SurefinanceMCP::Tools::Handlers::BudgetOps do
  subject(:tool) { described_class.new }

  let(:logger) { Logger.new(nil) }
  let!(:family) { SurefinanceMCP::Models::Family.create!(name: "Test Family") }

  before do
    SurefinanceMCP::Tools::BaseTool.server_context = { family_id: family.id, logger: logger }
  end

  describe "create" do
    it "bootstraps monthly budget" do
      result = tool.call(action: "create", payload: {
        start_date: "2025-01-01"
      })

      expect(result[:ok]).to eq(true)
      budget = result[:result][:budget]
      expect(budget[:start_date]).to eq("2025-01-01")
    end
  end

  describe "assign/remove category" do
    let!(:budget_id) do
      tool.call(action: "create", payload: { start_date: "2025-02-01" })[:result][:budget][:id]
    end

    let!(:category) do
      SurefinanceMCP::Models::Category.create!(
        family_id: family.id,
        name: "Groceries",
        color: "#ff0000",
        lucide_icon: "cart",
        classification: "expense"
      )
    end

    it "assigns and removes category" do
      assign = tool.call(action: "assign_category", payload: {
        budget_id: budget_id,
        category_id: category.id,
        budgeted_spending: 100
      })
      expect(assign[:ok]).to eq(true)

      remove = tool.call(action: "remove_category", payload: {
        budget_id: budget_id,
        category_id: category.id
      })
      expect(remove[:ok]).to eq(true)
    end
  end

  describe "progress" do
    it "returns totals" do
      budget_id = tool.call(action: "create", payload: { start_date: "2025-03-01" })[:result][:budget][:id]
      result = tool.call(action: "progress", payload: { id: budget_id })
      expect(result[:ok]).to eq(true)
    end
  end
end
