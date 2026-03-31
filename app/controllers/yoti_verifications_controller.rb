class YotiVerificationsController < ApplicationController
  include AhoyAnalytics

  before_action :set_identity
  before_action :ensure_yoti_accessible

  def new
    status = current_identity.verification_status
    if %w[verified ineligible].include?(status)
      redirect_to verification_status_path
      return
    end

    # If there's already a pending yoti verification, allow resuming
    @existing_verification = current_identity.yoti_verifications.pending.order(created_at: :desc).first

    if @existing_verification&.yoti_session_id.present?
      # Try to resume the existing session
      begin
        session_data = YotiService.instance.get_session(@existing_verification.yoti_session_id)
        if session_data[:state] == "COMPLETED"
          # Session already completed, process it
          Yoti::ProcessSessionJob.perform_later(session_id: @existing_verification.yoti_session_id)
          redirect_to verification_status_path
          return
        end
      rescue YotiService::YotiError
        # Session expired or invalid, create a new one
        @existing_verification = nil
      end
    end

    # Create a new Yoti session
    session_result = YotiService.instance.create_session(current_identity)

    @verification = Verification::YotiVerification.create!(
      identity: current_identity,
      yoti_session_id: session_result[:session_id],
      yoti_status: "CREATED",
      status: :pending
    )

    redirect_to session_result[:url], allow_other_host: true
  end

  def callback
    session_id = params[:sessionID] || params[:session_id]
    return head :bad_request if session_id.blank?

    # Server-side verification — never trust client status
    session_data = YotiService.instance.get_session(session_id)

    verification = find_or_create_verification(session_id, session_data)

    # Trigger processing
    if session_data[:state] == "COMPLETED"
      Yoti::ProcessSessionJob.perform_later(session_id: session_id)
    end

    render json: {
      status: verification.status,
      message: status_message_for(verification, session_data[:state])
    }
  rescue YotiService::YotiError => e
    Sentry.capture_exception(e)
    render json: { status: "error", message: "Something went wrong verifying your identity. Please try again." }, status: :unprocessable_entity
  end

  def status
    verification = current_identity.yoti_verifications.order(created_at: :desc).first

    if verification.nil?
      render json: { status: "none" }
    else
      render json: {
        status: verification.status,
        message: status_message_for(verification, verification.yoti_status)
      }
    end
  end

  private

  def set_identity
    @identity = current_identity
  end

  def ensure_yoti_accessible
    # Allow access if: Flipper is on for this user, OR they have a valid admin-issued bypass token
    return if current_identity.yoti_verification_enabled?
    return if valid_yoti_bypass_token?

    redirect_to new_verifications_path
  end

  def valid_yoti_bypass_token?
    token = params[:yoti_token]
    return false if token.blank?

    begin
      data = Rails.application.message_verifier("yoti_bypass").verify(token, purpose: :yoti_verification)
      data[:identity_id] == current_identity.id
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      false
    end
  end

  def self.generate_bypass_token(identity)
    Rails.application.message_verifier("yoti_bypass").generate(
      { identity_id: identity.id },
      purpose: :yoti_verification,
      expires_in: 7.days
    )
  end

  def find_or_create_verification(session_id, session_data)
    verification = Verification::YotiVerification.find_by(yoti_session_id: session_id)
    return verification if verification

    Verification::YotiVerification.create!(
      identity: current_identity,
      yoti_session_id: session_id,
      yoti_status: session_data[:state],
      status: :pending
    )
  end

  def status_message_for(verification, yoti_state)
    case verification.status
    when "approved"
      "Your identity has been verified!"
    when "rejected"
      verification.rejection_reason_name
    when "pending"
      if yoti_state == "COMPLETED"
        "Your ID is being automatically verified — this usually takes just a few minutes."
      else
        "Your verification is in progress."
      end
    end
  end
end
