# frozen_string_literal: true

require "spec_helper"

RSpec.describe SurefinanceMCP::Authentication do
  describe ".build" do
    it "returns a composite authenticator" do
      authenticator = described_class.build
      expect(authenticator).to respond_to(:authenticate)
    end
  end

  describe SurefinanceMCP::Authentication::Composite do
    subject(:composite) do
      strategies = [double(authenticate: nil), double(authenticate: { type: :api_key })]
      described_class.new(strategies: strategies, logger: Logger.new(nil))
    end

    let(:request) { instance_double(Rack::Request) }

    it "returns first successful authentication" do
      expect(composite.authenticate(request)).to eq(type: :api_key)
    end
  end
end
