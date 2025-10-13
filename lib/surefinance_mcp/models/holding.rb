# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class Holding < ActiveRecord::Base
      self.table_name = "holdings"

      belongs_to :account
    end
  end
end
