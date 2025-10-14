# frozen_string_literal: true

require "spec_helper"

RSpec.describe SurefinanceMCP::Tools::Handlers::AccountOps do
  subject(:tool) { described_class.new }

  let(:logger) { Logger.new(nil) }
  let!(:family) { SurefinanceMCP::Models::Family.create!(name: "Test Family") }

  before do
    SurefinanceMCP::Tools::BaseTool.server_context = { family_id: family.id, logger: logger }
  end

  describe "create/update" do
    it "creates and updates an account" do
      create = tool.call(action: "create", payload: {
        name: "Checking",
        type: "Depository",
        currency: "USD",
        opening_balance: 1000
      })
      expect(create[:ok]).to eq(true)
      account_id = create[:result][:account][:id]

      update = tool.call(action: "update", payload: {
        id: account_id,
        name: "Main Checking"
      })
      expect(update[:ok]).to eq(true)
    end
  end

  describe "close/reopen" do
    it "closes and reopens an account" do
      account_id = tool.call(action: "create", payload: {
        name: "Savings",
        type: "Depository",
        currency: "USD"
      })[:result][:account][:id]

      close = tool.call(action: "close", payload: { id: account_id, closed_on: "2025-01-31" })
      expect(close[:ok]).to eq(true)

      reopen = tool.call(action: "reopen", payload: { id: account_id })
      expect(reopen[:ok]).to eq(true)
    end
  end
end
