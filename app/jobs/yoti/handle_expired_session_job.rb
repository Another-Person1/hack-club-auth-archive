class Yoti::HandleExpiredSessionJob < ApplicationJob
  queue_as :default

  def perform(session_id:)
    verification = Verification::YotiVerification.find_by(yoti_session_id: session_id)
    return if verification.nil?
    return unless verification.pending?

    session_data = YotiService.instance.get_session(session_id)
    verification.update!(yoti_status: session_data[:state])

    verification.mark_as_rejected!("yoti_expired")

    # Also send the yoti-specific expiration email with a link to restart
    VerificationMailer.yoti_expired(verification).deliver_later
  rescue YotiService::YotiError => e
    Sentry.capture_exception(e)
    Rails.logger.error("[Yoti] Error handling expired session #{session_id}: #{e.message}")
  end
end
