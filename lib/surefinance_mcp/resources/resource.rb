# frozen_string_literal: true

module SurefinanceMCP
  module Resources
    class Resource
      attr_reader :scheme, :path_pattern, :description

      def initialize(scheme:, path_pattern:, description:, logger: SurefinanceMCP.logger)
        @scheme = scheme
        @path_pattern = Regexp.new(path_pattern)
        @description = description
        @logger = logger
      end

      def match?(uri)
        uri.scheme == scheme && uri.path.match?(path_pattern)
      end

      def to_h
        {
          scheme: scheme,
          path_pattern: path_pattern.source,
          description: description
        }
      end

      private

      attr_reader :logger
    end
  end
end
}