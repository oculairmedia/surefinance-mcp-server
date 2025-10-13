# frozen_string_literal: true

module SurefinanceMCP
  module Resources
    class HttpHandler
      def initialize(registry:, authenticator:, database:, logger: SurefinanceMCP.logger)
        @registry = registry
        @authenticator = authenticator
        @database = database
        @logger = logger
      end

      def call(request, auth_context = nil)
        @auth_context = auth_context || authenticator.authenticate(request)
        return unauthorized unless @auth_context

        case request.request_method
        when "GET"
          if request.path == "/resources"
            list_resources
          else
            resolve_resource(request)
          end
        else
          response(405, { error: "Method not allowed" })
        end
      end

      private

      attr_reader :registry, :authenticator, :database, :logger

      def list_resources
        response(200, { resources: registry.list })
      end

      def resolve_resource(request)
        uri = URI(request.params["uri"] || request.path)
        resource = registry.find(uri)
        raise SurefinanceMCP::Errors::NotFound, "Resource not found" unless resource

        result = resource.call(uri, auth: @auth_context)
        response(200, result)
      rescue SurefinanceMCP::Errors::NotFound => e
        response(404, { error: e.message })
      rescue StandardError => e
        logger.error("Resource resolution failed: #{e.message}")
        response(500, { error: "Internal server error" })
      end

      def response(status, body)
        [status, { "Content-Type" => "application/json" }, [JSON.dump(body)]]
      end

      def unauthorized
        response(401, { error: "Unauthorized" })
      end
    end
  end
end
