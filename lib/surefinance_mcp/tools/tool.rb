# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    Tool = Struct.new(:name, :description, :parameters, :handler, keyword_init: true) do
      def call(context)
        handler.call(context)
      end

      def to_h
        {
          name: name,
          description: description,
          parameters: parameters
        }
      end
    end
  end
end
