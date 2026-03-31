module Webhooks
  class YotiController < ApplicationController
    before_action :verify_yoti_signature

    def create
      session_id = params.dig(:session_id)
      topic = params.dig(:topic)

      if session_id.blank?
        head :ok
        return
      end

      case topic
      when "session_completion", "check_completion"
        Yoti::ProcessSessionJob.perform_later(session_id: session_id)
      when "session_expiry"
        Yoti::HandleExpiredSessionJob.perform_later(session_id: session_id)
      else
        Rails.logger.info("[Yoti Webhook] Received topic: #{topic} for session #{session_id}")
      end

      head :ok
    end

    private

    def verify_yoti_signature
      unless YotiService.instance.verify_webhook_signature(request)
        head :unauthorized
      end
    end
  end
end
