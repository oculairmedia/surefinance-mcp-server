# frozen_string_literal: true

require "spec_helper"

RSpec.describe SurefinanceMCP::Tools::Handlers::TransactionOps do
  subject(:tool) { described_class.new }

  let(:logger) { Logger.new(nil) }
  let!(:family) { SurefinanceMCP::Models::Family.create!(name: "Test Family") }
  let!(:account) { SurefinanceMCP::Models::Account.create!(family: family, name: "Checking") }

  before do
    SurefinanceMCP::Tools::BaseTool.server_context = { family_id: family.id, logger: logger }
  end

  describe "create/update/delete" do
    it "creates updates and deletes a transaction" do
      create = tool.call(action: "create", payload: {
        account_id: account.id,
        amount: 50.0,
        date: "2025-01-15",
        description: "Lunch",
        memo: "Team lunch"
      })
      expect(create[:ok]).to eq(true)
      txn_id = create[:result][:transaction][:id]

      update = tool.call(action: "update", payload: {
        id: txn_id,
        amount: 55.0,
        description: "Lunch with team"
      })
      expect(update[:ok]).to eq(true)

      delete = tool.call(action: "delete", payload: { id: txn_id })
      expect(delete[:ok]).to eq(true)
    end
  end

  describe "categorize" do
    let!(:category) do
      SurefinanceMCP::Models::Category.create!(
        family: family,
        name: "Dining",
        color: "#ff0000",
        lucide_icon: "utensils",
        classification: "expense"
      )
    end

    it "categorizes transaction" do
      txn_id = tool.call(action: "create", payload: {
        account_id: account.id,
        amount: 20,
        date: "2025-02-01"
      })[:result][:transaction][:id]

      result = tool.call(action: "categorize", payload: {
        id: txn_id,
        category_id: category.id
      })
      expect(result[:ok]).to eq(true)
    end
  end
end
