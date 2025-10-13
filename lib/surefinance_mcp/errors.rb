# frozen_string_literal: true

module SurefinanceMCP
  module Errors
    class NotFound < StandardError; end
    class ValidationError < StandardError; end
    class Unauthorized < StandardError; end
  end
end
