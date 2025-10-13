# frozen_string_literal: true

require "spec_helper"

RSpec.describe SurefinanceMCP::Resources::Registry do
  subject(:registry) { described_class.new(logger: Logger.new(nil)) }

  describe "#find" do
    it "finds a resource matching the URI" do
      uri = URI("surefinance://accounts/123")
      resource = registry.find(uri)
      expect(resource).not_to be_nil
      expect(resource.description).to include("Account")
    end
  end
end
