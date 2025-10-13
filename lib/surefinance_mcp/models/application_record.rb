# frozen_string_literal: true

require "active_support"
require "active_support/core_ext"

module SurefinanceMCP
  module Models
    class ApplicationRecord < ActiveRecord::Base
      primary_abstract_class
    end
  end
end
