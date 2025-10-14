# frozen_string_literal: true

require "spec_helper"
require "rack/test"
require "json"

RSpec.describe "SureFinance MCP JSON-RPC" do
  include Rack::Test::Methods

  let(:db_double) { instance_double("ActiveRecord::Base") }
  let(:auth_double) { instance_double("Authenticator", authenticate: { family_id: "test-family" }) }

  before do
    SurefinanceMCP.instance_variable_set(:@server, nil)
    ENV["MCP_SERVER_ENV"] = "test"
    allow(SurefinanceMCP::Database).to receive(:build).and_return(db_double)
    allow(SurefinanceMCP::Authentication).to receive(:build).and_return(auth_double)
    SurefinanceMCP::Tools::BaseTool.server_context = {
      logger: SurefinanceMCP.logger,
      database: db_double,
      authenticator: auth_double,
      family_id: "test-family"
    }
    header "Content-Type", "application/json"
  end

  after do
    SurefinanceMCP.instance_variable_set(:@server, nil)
    SurefinanceMCP::Tools::BaseTool.server_context = nil
  end

  def app
    server = SurefinanceMCP.server
    SurefinanceMCP::Tools::BaseTool.server_context ||= server.server_context
    server.app
  end

  describe "POST /mcp/messages" do
    it "lists registered tools" do
      post "/mcp/messages", {
        jsonrpc: "2.0",
        id: 1,
        method: "tools/list"
      }.to_json

      expect(last_response.status).to eq(200)

      body = JSON.parse(last_response.body)
      expect(body["jsonrpc"]).to eq("2.0")
      expect(body["id"]).to eq(1)
      expect(body.dig("result", "tools")).to be_an(Array)
      expect(body.dig("result", "tools").map { |tool| tool["name"] })
        .to include("show_accounts", "show_budgets", "find_transactions")
    end

    it "returns tool execution results" do
      # Stub the tool class to return a mock instance
      mock_tool = instance_double(SurefinanceMCP::Tools::Handlers::GetAccounts)
      allow(mock_tool).to receive(:call).and_return({ accounts: [] })
      allow(mock_tool).to receive(:authorized?).and_return(true)
      allow(mock_tool).to receive(:call_with_schema_validation!).and_return({ accounts: [] })

      # Stub the class method that creates tool instances
      allow(SurefinanceMCP::Tools::Handlers::GetAccounts)
        .to receive(:new).with(anything).and_return(mock_tool)

      post "/mcp/messages", {
        jsonrpc: "2.0",
        id: 2,
        method: "tools/call",
        params: {
          name: "show_accounts",
          arguments: {}
        }
      }.to_json

      expect(last_response.status).to eq(200)

      body = JSON.parse(last_response.body)
      expect(body["jsonrpc"]).to eq("2.0")
      expect(body["id"]).to eq(2)
      expect(body.dig("result", "content")).to be_an(Array)
      # FastMCP returns JSON results with type "application/json" or "text"
      expect(body.dig("result", "content").first["type"]).to match(/json|text/)
    end

    it "returns validation errors" do
      post "/mcp/messages", {
        jsonrpc: "2.0",
        id: 3,
        method: "tools/call",
        params: {
          name: "show_balance_history",
          arguments: {}
        }
      }.to_json

      expect(last_response.status).to eq(200)

      body = JSON.parse(last_response.body)
      expect(body["jsonrpc"]).to eq("2.0")
      expect(body["id"]).to eq(3)
      # FastMCP returns validation errors in result with isError: true
      expect(body.dig("result", "isError")).to be(true)
      expect(body.dig("result", "content")).to be_an(Array)
      # Check that the error message mentions account_id
      error_text = body.dig("result", "content", 0, "text")
      expect(error_text).to match(/account_id/i)
    end
  end
end
