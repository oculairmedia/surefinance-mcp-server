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

  describe "action: create" do
    it "creates linked transfer with debit and credit transactions" do
      initial_txn_count = SurefinanceMCP::Models::Transaction.count
      initial_entry_count = SurefinanceMCP::Models::Entry.count

      result = tool.call(
        action: "create",
        from_account_id: from_account.id,
        to_account_id: to_account.id,
        amount: 100,
        memo: "Transfer"
      )

      expect(result[:ok]).to eq(true)
      expect(result[:result]).to include(:debit_txn, :credit_txn)

      # Verify both transactions were created
      expect(SurefinanceMCP::Models::Transaction.count).to eq(initial_txn_count + 2)

      # Verify both entries were created
      expect(SurefinanceMCP::Models::Entry.count).to eq(initial_entry_count + 2)

      # Verify amounts
      debit_txn = result[:result][:debit_txn]
      credit_txn = result[:result][:credit_txn]

      expect(debit_txn[:amount]).to eq(-100.0)
      expect(credit_txn[:amount]).to eq(100.0)
    end

    it "creates transfer with custom date" do
      result = tool.call(
        action: "create",
        from_account_id: from_account.id,
        to_account_id: to_account.id,
        amount: 50.75,
        date: "2025-01-15",
        description: "Scheduled transfer"
      )

      expect(result[:ok]).to eq(true)
      expect(result[:result][:debit_txn][:date]).to eq("2025-01-15")
      expect(result[:result][:credit_txn][:date]).to eq("2025-01-15")
    end

    it "accepts integer amounts" do
      result = tool.call(
        action: "create",
        from_account_id: from_account.id,
        to_account_id: to_account.id,
        amount: 100
      )

      expect(result[:ok]).to eq(true)
    end

    it "accepts float amounts" do
      result = tool.call(
        action: "create",
        from_account_id: from_account.id,
        to_account_id: to_account.id,
        amount: 99.99
      )

      expect(result[:ok]).to eq(true)
    end

    context "atomicity and rollback" do
      it "rolls back both entries if transaction creation fails" do
        initial_txn_count = SurefinanceMCP::Models::Transaction.count
        initial_entry_count = SurefinanceMCP::Models::Entry.count

        # Stub the second transaction creation to fail
        allow(SurefinanceMCP::Models::Transaction).to receive(:new).and_call_original
        allow(SurefinanceMCP::Models::Transaction).to receive(:new).and_call_original.once
        allow(SurefinanceMCP::Models::Transaction).to receive(:new).and_raise(ActiveRecord::RecordInvalid.new)

        result = tool.call(
          action: "create",
          from_account_id: from_account.id,
          to_account_id: to_account.id,
          amount: 100
        )

        # Should return error
        expect(result[:ok]).to eq(false)

        # Neither transaction nor entry should be persisted
        expect(SurefinanceMCP::Models::Transaction.count).to eq(initial_txn_count)
        expect(SurefinanceMCP::Models::Entry.count).to eq(initial_entry_count)
      end

      it "rolls back all records if entry creation fails" do
        initial_txn_count = SurefinanceMCP::Models::Transaction.count
        initial_entry_count = SurefinanceMCP::Models::Entry.count

        # Stub the second entry creation to fail
        allow(SurefinanceMCP::Models::Entry).to receive(:create!).and_call_original.once
        allow(SurefinanceMCP::Models::Entry).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new)

        result = tool.call(
          action: "create",
          from_account_id: from_account.id,
          to_account_id: to_account.id,
          amount: 100
        )

        # Should return error
        expect(result[:ok]).to eq(false)

        # No records should be persisted due to rollback
        expect(SurefinanceMCP::Models::Transaction.count).to eq(initial_txn_count)
        expect(SurefinanceMCP::Models::Entry.count).to eq(initial_entry_count)
      end

      it "rolls back if linking transactions fails" do
        # Skip if transfer_transaction_id column doesn't exist
        skip "transfer_transaction_id column not present" unless SurefinanceMCP::Models::Transaction.column_names.include?("transfer_transaction_id")

        initial_txn_count = SurefinanceMCP::Models::Transaction.count
        initial_entry_count = SurefinanceMCP::Models::Entry.count

        # Stub update to fail during linking
        allow_any_instance_of(SurefinanceMCP::Models::Transaction).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new)

        result = tool.call(
          action: "create",
          from_account_id: from_account.id,
          to_account_id: to_account.id,
          amount: 100
        )

        # Should return error
        expect(result[:ok]).to eq(false)

        # No records should be persisted due to rollback
        expect(SurefinanceMCP::Models::Transaction.count).to eq(initial_txn_count)
        expect(SurefinanceMCP::Models::Entry.count).to eq(initial_entry_count)
      end
    end

    context "validation errors" do
      it "rejects negative amounts" do
        result = tool.call(
          action: "create",
          from_account_id: from_account.id,
          to_account_id: to_account.id,
          amount: -50
        )

        expect(result[:ok]).to eq(false)
        expect(result[:error][:type]).to eq("validation_error")
        expect(result[:error][:message]).to include("positive")
      end

      it "rejects zero amounts" do
        result = tool.call(
          action: "create",
          from_account_id: from_account.id,
          to_account_id: to_account.id,
          amount: 0
        )

        expect(result[:ok]).to eq(false)
        expect(result[:error][:type]).to eq("validation_error")
      end

      it "returns not_found error for invalid from_account" do
        result = tool.call(
          action: "create",
          from_account_id: "00000000-0000-0000-0000-000000000000",
          to_account_id: to_account.id,
          amount: 100
        )

        expect(result[:ok]).to eq(false)
        expect(result[:error][:type]).to eq("not_found")
      end

      it "returns not_found error for invalid to_account" do
        result = tool.call(
          action: "create",
          from_account_id: from_account.id,
          to_account_id: "00000000-0000-0000-0000-000000000000",
          amount: 100
        )

        expect(result[:ok]).to eq(false)
        expect(result[:error][:type]).to eq("not_found")
      end

      it "returns validation error for missing from_account_id" do
        result = tool.call(
          action: "create",
          to_account_id: to_account.id,
          amount: 100
        )

        expect(result[:ok]).to eq(false)
        expect(result[:error][:type]).to eq("validation_error")
      end

      it "returns validation error for missing to_account_id" do
        result = tool.call(
          action: "create",
          from_account_id: from_account.id,
          amount: 100
        )

        expect(result[:ok]).to eq(false)
        expect(result[:error][:type]).to eq("validation_error")
      end

      it "returns validation error for missing amount" do
        result = tool.call(
          action: "create",
          from_account_id: from_account.id,
          to_account_id: to_account.id
        )

        expect(result[:ok]).to eq(false)
        expect(result[:error][:type]).to eq("validation_error")
      end

      it "returns validation error for invalid date format" do
        result = tool.call(
          action: "create",
          from_account_id: from_account.id,
          to_account_id: to_account.id,
          amount: 100,
          date: "invalid-date"
        )

        expect(result[:ok]).to eq(false)
        expect(result[:error][:type]).to eq("validation_error")
      end
    end

    context "family scoping" do
      let!(:other_family) { SurefinanceMCP::Models::Family.create!(name: "Other Family") }
      let!(:other_account) { SurefinanceMCP::Models::Account.create!(family: other_family, name: "Other Account") }

      it "rejects transfer from account in different family" do
        result = tool.call(
          action: "create",
          from_account_id: other_account.id,
          to_account_id: to_account.id,
          amount: 100
        )

        expect(result[:ok]).to eq(false)
        expect(result[:error][:type]).to eq("not_found")
      end

      it "rejects transfer to account in different family" do
        result = tool.call(
          action: "create",
          from_account_id: from_account.id,
          to_account_id: other_account.id,
          amount: 100
        )

        expect(result[:ok]).to eq(false)
        expect(result[:error][:type]).to eq("not_found")
      end
    end
  end
end
