# frozen_string_literal: true

require "spec_helper"

RSpec.describe SurefinanceMCP::Tools::AccountsTools do
  subject(:accounts_tools) { described_class.new(logger: Logger.new(nil)) }

  describe "#tools" do
    it "includes get_accounts tool" do
      tool = accounts_tools.tools.find { |t| t.name == "get_accounts" }
      expect(tool).not_to be_nil
      expect(tool.parameters[:properties]).to include(:updated_since)
      expect(tool.handler).to respond_to(:call)
    end
  end
end
