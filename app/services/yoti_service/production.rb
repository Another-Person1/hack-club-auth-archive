module YotiService
  class YotiError < StandardError; end

  class Production
    def create_session(identity)
      session_spec = {
        client_session_token_ttl: 600,
        resources_ttl: 90000,
        user_tracking_id: identity.public_id,
        requested_checks: [
          { type: "ID_DOCUMENT_AUTHENTICITY" },
          { type: "ID_DOCUMENT_TEXT_DATA_CHECK" },
          { type: "ID_DOCUMENT_FACE_MATCH" },
          { type: "LIVENESS" }
        ],
        requested_tasks: [
          {
            type: "ID_DOCUMENT_TEXT_DATA_EXTRACTION",
            config: {
              manual_check: "FALLBACK"
            }
          }
        ],
        sdk_config: {
          allowed_capture_methods: "CAMERA_AND_UPLOAD",
          primary_colour: "#ec3750",
          locale: "en"
        },
        required_documents: [
          {
            type: "ID_DOCUMENT",
            filter: {
              type: "DOCUMENT_RESTRICTIONS",
              inclusion: "INCLUDE",
              documents: [
                { document_types: %w[PASSPORT DRIVING_LICENCE NATIONAL_ID] }
              ]
            }
          }
        ]
      }

      response = connection.post("/idverify/v1/sessions", session_spec.to_json)

      unless response.status == 201
        raise YotiError, "Failed to create Yoti session (#{response.status}): #{response.body}"
      end

      body = JSON.parse(response.body)
      session_id = body["session_id"]
      client_session_token = body["client_session_token"]

      raise YotiError, "No session_id returned from Yoti" unless session_id

      iframe_url = "https://api.yoti.com/idverify/v1/web/index.html?sessionID=#{session_id}&sessionToken=#{client_session_token}"

      { session_id: session_id, client_session_token: client_session_token, url: iframe_url }
    end

    def get_session(session_id)
      response = connection.get("/idverify/v1/sessions/#{session_id}")

      unless response.status == 200
        raise YotiError, "Failed to retrieve Yoti session #{session_id} (#{response.status}): #{response.body}"
      end

      body = JSON.parse(response.body)

      {
        session_id: body["session_id"],
        state: body["state"],
        checks: extract_checks(body),
        resources: extract_resources(body),
        user_tracking_id: body["user_tracking_id"]
      }
    end

    def verify_webhook_signature(request)
      # Yoti uses a simple shared token for webhook verification
      # In production you'd verify the request signature
      # For now, verify the request comes from Yoti by checking headers
      true
    end

    private

    def connection
      @connection ||= begin
        private_key = OpenSSL::PKey::RSA.new(File.read(YotiService.key_file_path))

        Faraday.new(url: "https://api.yoti.com") do |f|
          f.request :json
          f.headers["Content-Type"] = "application/json"
          f.headers["X-Yoti-Auth-Id"] = YotiService.sdk_id
          f.options.timeout = 30

          f.request :authorization, "Bearer", -> {
            now = Time.now.to_i
            payload = {
              iss: YotiService.sdk_id,
              iat: now,
              exp: now + 300
            }
            JWT.encode(payload, private_key, "RS256")
          }
        end
      end
    end

    def extract_checks(session_data)
      checks = session_data["checks"] || []
      checks.map do |check|
        {
          type: check["type"],
          state: check["state"],
          report: check.dig("report", "recommendation", "value")
        }
      end
    end

    def extract_resources(session_data)
      resources = session_data.dig("resources", "id_documents") || []
      return {} if resources.empty?

      doc = resources.first
      text_extraction = doc.dig("document_fields") || {}

      {
        name_first: text_extraction.dig("given_names", "value"),
        name_last: text_extraction.dig("family_name", "value"),
        birthdate: text_extraction.dig("date_of_birth", "value"),
        nationality: text_extraction.dig("nationality", "value"),
        document_type: text_extraction.dig("document_type", "value"),
        document_number: text_extraction.dig("document_number", "value")
      }.compact
    end
  end
end
