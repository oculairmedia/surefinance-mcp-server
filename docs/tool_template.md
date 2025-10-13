# Fast‑MCP Tool Template (Skeleton)

Use this as a starting point when converting tools.

```ruby
# frozen_string_literal: true

module SurefinanceMCP
  module Tools
    class ExampleTool < FastMcp::Tool
      description "Clear description"

      arguments do
        required(:arg1).filled(:string).description("Arg1 description")
        optional(:limit).filled(:integer).description("Max results (default 100)")
      end

      def call(arg1:, limit: 100)
        family_id = server_context[:family_id]
        # TODO: implement logic
        { result: true }
      rescue ArgumentError => e
        { error: e.message }
      end

      private

      def logger
        SurefinanceMCP.logger
      end

      def server_context
        # Injected by server per SFMCP-21
        { family_id: ENV.fetch("DEFAULT_FAMILY_ID") }
      end
    end
  end
end
```

Checklist:
- [ ] Inherit from FastMcp::Tool
- [ ] Define arguments with dry‑schema
- [ ] Use server_context for family_id
- [ ] Return plain hashes (Fast‑MCP wraps)
- [ ] Add tests (JSON‑RPC tools/call)
