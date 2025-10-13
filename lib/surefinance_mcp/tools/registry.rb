# frozen_string_literal: true

require_relative "tool"
require_relative "accounts_tools"
require_relative "transactions_tools"
require_relative "budgets_tools"
require_relative "categories_tools"

module SurefinanceMCP
  module Tools
    class Registry
      def initialize(logger: SurefinanceMCP.logger)
        @logger = logger
        @tools = build_tools
      end

      def find_tool(name)
        tools.find { |tool| tool.name == name }
      end

      def list
        tools.map(&:to_h)
      end

      private

      attr_reader :tools, :logger

      def build_tools
        [
          AccountsTools.new(logger: logger).tools,
          TransactionsTools.new(logger: logger).tools,
          BudgetsTools.new(logger: logger).tools,
          CategoriesTools.new(logger: logger).tools
        ].flatten
      end
    end
  end
end
