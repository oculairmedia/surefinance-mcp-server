# frozen_string_literal: true

module SurefinanceMCP
  module Models
    class AccountBalanceHistory < ActiveRecord::Base
      self.table_name = "account_balances"

      scope :for_account, lambda { |account_id, range|
        window_start = case range
                        when "30d"
                          30.days.ago.to_date
                        when "90d"
                          90.days.ago.to_date
                        when "1y"
                          1.year.ago.to_date
                        else
                          90.days.ago.to_date
                        end

        where(account_id: account_id)
          .where("date >= ?", window_start)
          .order(date: :asc)
      }
    end
  end
end
