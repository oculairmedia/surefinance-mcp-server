# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class Entry < ApplicationRecord
      self.table_name = "entries"

      belongs_to :account
      belongs_to :entryable, polymorphic: true

      scope :for_family, ->(family_id) { joins(:account).where(accounts: { family_id: family_id }) }

      delegate :family_id, to: :account
      delegate :family, to: :account
    end
  end
end
