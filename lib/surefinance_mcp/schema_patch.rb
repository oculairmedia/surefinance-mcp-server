# frozen_string_literal: true

puts "=== Loading schema_patch.rb ==="

# Patch to add items to array schemas for OpenAI compatibility
module FastMcp
  class Tool
    class << self
      # Store the original input_schema method
      alias_method :input_schema_original, :input_schema

      # Override to add items to arrays
      def input_schema
        puts "=== input_schema called for #{name} ==="
        schema = input_schema_original
        puts "=== Original schema: #{schema.inspect[0..200]} ==="

        # Recursively add items to arrays
        add_items_to_arrays(schema)
        puts "=== Patched schema: #{schema.inspect[0..200]} ==="

        schema
      end

      private

      def add_items_to_arrays(obj)
        case obj
        when Hash
          # If this is an array without items, add a generic object items schema
          if obj[:type] == "array" && !obj[:items]
            puts "=== Adding items to array property ==="
            obj[:items] = { type: "object" }
          end
          # Recursively process nested hashes
          obj.each_value { |v| add_items_to_arrays(v) }
        when Array
          # Recursively process arrays
          obj.each { |item| add_items_to_arrays(item) }
        end
      end
    end
  end
end

puts "=== schema_patch.rb loaded ==="
