module YotiService
  class Mock
    def create_session(identity)
      session_id = "mock_session_#{SecureRandom.hex(8)}"
      client_session_token = "mock_token_#{SecureRandom.hex(8)}"

      {
        session_id: session_id,
        client_session_token: client_session_token,
        url: "https://api.yoti.com/idverify/v1/web/index.html?sessionID=#{session_id}&sessionToken=#{client_session_token}"
      }
    end

    def get_session(session_id)
      {
        session_id: session_id,
        state: "COMPLETED",
        checks: [
          { type: "ID_DOCUMENT_AUTHENTICITY", state: "DONE", report: "APPROVE" },
          { type: "ID_DOCUMENT_TEXT_DATA_CHECK", state: "DONE", report: "APPROVE" },
          { type: "ID_DOCUMENT_FACE_MATCH", state: "DONE", report: "APPROVE" },
          { type: "LIVENESS", state: "DONE", report: "APPROVE" }
        ],
        resources: {
          name_first: "Test",
          name_last: "User",
          birthdate: "2010-01-15"
        },
        user_tracking_id: "mock_reference"
      }
    end

    def verify_webhook_signature(_request)
      true
    end
  end
end
