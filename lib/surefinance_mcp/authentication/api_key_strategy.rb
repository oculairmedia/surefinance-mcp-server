# frozen_string_literal: true

module SurefinanceMCP
  module Authentication
    class ApiKeyStrategy
      ENV_KEY_MAP = "API_KEYS"
      ENV_SINGLE_KEY = "API_KEY"
      ENV_SINGLE_FAMILY = "DEFAULT_FAMILY_ID"

      def initialize(header: "X-Api-Key", key_map: nil, logger: SurefinanceMCP.logger)
        @header = header
        @key_map = key_map || load_key_map
        @logger = logger
      end

      def authenticate(request)
        logger.info("API Key auth: key_map has #{key_map.size} entries")
        return nil if key_map.empty?

        header_name = header_env_name
        provided = request.get_header(header_name)
        logger.info("API Key auth: looking for header '#{header_name}', got: '#{provided ? provided[0..20] + '...' : 'nil'}'")
        return nil unless provided

        family_id = key_map[provided]
        logger.info("API Key auth: mapped to family_id: #{family_id}")
        return nil unless family_id

        { type: :api_key, family_id: family_id }
      end

      private

      attr_reader :header, :key_map, :logger

      def header_env_name
        "HTTP_#{header.upcase.tr('-', '_')}"
      end

      def load_key_map
        map = {}

        env_keys = ENV.fetch(ENV_KEY_MAP, nil)
        if env_keys
          env_keys.split(",").each do |entry|
            key, family = entry.split(":", 2).map { |value| value&.strip }
            next if family.nil? || key.nil? || family.empty? || key.empty?

            # Support both integer IDs and UUID strings
            map[key] = parse_family_id(family)
          end
        end

        if map.empty?
          single_key = ENV.fetch(ENV_SINGLE_KEY, nil)
          single_family = ENV.fetch(ENV_SINGLE_FAMILY, nil)
          if single_key && single_family
            map[single_key] = parse_family_id(single_family)
          end
        end

        map.compact
      end

      def parse_family_id(value)
        # Try to parse as integer first (for numeric IDs)
        int_value = Integer(value, exception: false)
        return int_value if int_value

        # If not an integer, return as string (for UUIDs)
        value
      end
    end
  end
end
