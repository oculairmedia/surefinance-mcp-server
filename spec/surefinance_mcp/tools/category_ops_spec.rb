# frozen_string_literal: true

require "spec_helper"

RSpec.describe SurefinanceMCP::Tools::Handlers::CategoryOps do
  subject(:tool) { described_class.new }

  let(:logger) { Logger.new(nil) }
  let(:family_id) { family.id }
  let(:server_context) { { family_id: family_id, logger: logger } }

  before do
    SurefinanceMCP::Tools::BaseTool.server_context = server_context
  end

  let!(:family) { SurefinanceMCP::Models::Family.create!(name: "Test Fam") }

  describe "action=create" do
    it "creates a root category with required fields" do
      result = tool.call(action: "create", payload: {
        name: "Travel",
        classification: "expense",
        lucide_icon: "plane",
        color: "#ff0000"
      })

      expect(result[:ok]).to eq(true)
      expect(result[:result][:category]).to include(name: "Travel", color: "#ff0000")
    end

    it "rejects duplicate name" do
      tool.call(action: "create", payload: {
        name: "Travel",
        classification: "expense",
        lucide_icon: "plane",
        color: "#ff0000"
      })

      result = tool.call(action: "create", payload: {
        name: "Travel",
        classification: "expense",
        lucide_icon: "boat",
        color: "#00ff00"
      })

      expect(result[:ok]).to eq(false)
      expect(result[:error][:type]).to eq("validation_error")
    end

    it "inherits color from parent" do
      parent = tool.call(action: "create", payload: {
        name: "Food",
        classification: "expense",
        lucide_icon: "utensils",
        color: "#eb5429"
      })[:result][:category]

      result = tool.call(action: "create", payload: {
        name: "Dining Out",
        classification: "expense",
        parent_id: parent[:id],
        lucide_icon: "utensils"
      })

      expect(result[:ok]).to eq(true)
      expect(result[:result][:category]).to include(parent_id: parent[:id], color: "#eb5429")
    end
  end

  describe "action=update" do
    let(:category) do
      tool.call(action: "create", payload: {
        name: "Travel",
        classification: "expense",
        lucide_icon: "plane",
        color: "#ff0000"
      })[:result][:category]
    end

    it "updates name and lucide_icon" do
      result = tool.call(action: "update", payload: {
        id: category[:id],
        name: "Vacation",
        lucide_icon: "suitcase"
      })

      expect(result[:ok]).to eq(true)
      expect(result[:result][:category]).to include(name: "Vacation", lucide_icon: "suitcase")
    end

    it "rejects duplicate name" do
      tool.call(action: "create", payload: {
        name: "Other",
        classification: "expense",
        lucide_icon: "plane",
        color: "#00ff00"
      })

      result = tool.call(action: "update", payload: {
        id: category[:id],
        name: "Other"
      })

      expect(result[:ok]).to eq(false)
      expect(result[:error][:type]).to eq("validation_error")
    end

    it "propagates color to children" do
      child = tool.call(action: "create", payload: {
        name: "Flights",
        classification: "expense",
        parent_id: category[:id],
        lucide_icon: "plane"
      })[:result][:category]

      result = tool.call(action: "update", payload: {
        id: category[:id],
        color: "#00ff00"
      })

      expect(result[:ok]).to eq(true)

      updated_child = SurefinanceMCP::Models::Category.find(child[:id])
      expect(updated_child.color).to eq("#00ff00") if updated_child.respond_to?(:color)
    end
  end

  describe "action=move" do
    let!(:root1) do
      tool.call(action: "create", payload: {
        name: "Income",
        classification: "income",
        lucide_icon: "circle-dollar-sign",
        color: "#e99537"
      })[:result][:category]
    end

    let!(:root2) do
      tool.call(action: "create", payload: {
        name: "Salary",
        classification: "income",
        lucide_icon: "briefcase",
        color: "#4da568"
      })[:result][:category]
    end

    let!(:child) do
      tool.call(action: "create", payload: {
        name: "Bonus",
        classification: "income",
        parent_id: root1[:id],
        lucide_icon: "award"
      })[:result][:category]
    end

    it "moves child to another root and inherits color" do
      result = tool.call(action: "move", payload: {
        id: child[:id],
        new_parent_id: root2[:id]
      })

      expect(result[:ok]).to eq(true)
      expect(result[:result][:category]).to include(parent_id: root2[:id])

      moved = SurefinanceMCP::Models::Category.find(child[:id])
      expect(moved.parent_id).to eq(root2[:id])
      expect(moved.color).to eq("#4da568") if moved.respond_to?(:color)
    end

    it "rejects third-level move" do
      grandchild = tool.call(action: "create", payload: {
        name: "Year-end Bonus",
        classification: "income",
        parent_id: child[:id],
        lucide_icon: "gift"
      })[:result][:category]

      result = tool.call(action: "move", payload: {
        id: grandchild[:id],
        new_parent_id: child[:id]
      })

      expect(result[:ok]).to eq(false)
    end
  end

  describe "action=delete" do
    let!(:category) do
      tool.call(action: "create", payload: {
        name: "Travel",
        classification: "expense",
        lucide_icon: "plane",
        color: "#ff0000"
      })[:result][:category]
    end

    it "deletes leaf category without replacement" do
      result = tool.call(action: "delete", payload: { id: category[:id] })

      expect(result[:ok]).to eq(true)
      expect(result[:result]).to include(destroyed: true)
    end
  end

  describe "action=merge" do
    let!(:cat_a) do
      tool.call(action: "create", payload: {
        name: "Dining",
        classification: "expense",
        lucide_icon: "utensils",
        color: "#eb5429"
      })[:result][:category]
    end

    let!(:cat_b) do
      tool.call(action: "create", payload: {
        name: "Restaurants",
        classification: "expense",
        lucide_icon: "utensils",
        color: "#eb5429"
      })[:result][:category]
    end

    it "merges categories" do
      result = tool.call(action: "merge", payload: {
        source_id: cat_a[:id],
        target_id: cat_b[:id]
      })

      expect(result[:ok]).to eq(true)
      expect(result[:result]).to include(merged: true)
    end
  end
end
