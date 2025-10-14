# frozen_string_literal: true

require "spec_helper"

RSpec.describe SurefinanceMCP::Tools::Handlers::TransferOps do
  subject(:tool) { described_class.new }

  let(:logger) { Logger.new(nil) }
  let!(:family) { SurefinanceMCP::Models::Family.create!(name: "Test Family") }
  let!(:from_account) { SurefinanceMCP::Models::Account.create!(family: family, name: "Checking") }
  let!(:to_account) { SurefinanceMCP::Models::Account.create!(family: family, name: "Savings") }

  before do
    SurefinanceMCP::Tools::BaseTool.server_context = { family_id: family.id, logger: logger }
  end

  it "creates linked transfer" do
    result = tool.call(action: "create", payload: {
      from_account_id: from_account.id,
      to_account_id: to_account.id,
      amount: 100,
      memo: "Transfer"
    })

    expect(result[:ok]).to eq(true)
    expect(result[:result]).to include(:debit_txn, :credit_txn)
  end
end
