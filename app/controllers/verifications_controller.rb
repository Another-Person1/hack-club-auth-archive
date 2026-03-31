class VerificationsController < ApplicationController
  include Wicked::Wizard
  include VerificationFlow
  include AhoyAnalytics

  before_action :set_identity

  steps :document

  def new
    status = current_identity.verification_status
    if verification_should_redirect?(status)
      redirect_to verification_status_path
      return
    end

    # If Yoti is enabled, route to method choice (or directly to Yoti for forced-Yoti countries)
    if current_identity.yoti_verification_enabled?
      redirect_to choose_verification_method_path
      return
    end

    redirect_to verification_step_path(:document)
  end

  def choose_method
    status = current_identity.verification_status
    if verification_should_redirect?(status)
      redirect_to verification_status_path
      return
    end

    unless current_identity.yoti_verification_enabled?
      redirect_to verification_step_path(:document)
      return
    end

    @identity = current_identity
    @show_transcript_option = Identity::Document.selectable_types_for_country(current_identity.country).include?(:transcript)
  end

  def status
    @identity = current_identity
    @status = @identity.verification_status
    @latest_verification = @identity.latest_verification
  end

  def show
    @identity = current_identity

    status = @identity.verification_status
    if verification_should_redirect?(status)
      redirect_to verification_status_path
      return
    end

    case step
    when :document
      setup_document_step
    end

    render_wizard
  end

  def update
    @identity = current_identity

    case step
    when :document
      handle_document_submission
    end
  end

  private

  def set_identity
    @identity = current_identity
  end

  def on_verification_success
    track_event("verification.submitted", verification_type: "document", scenario: analytics_scenario_for(@identity))
    flash[:success] = "Your documents have been submitted for review! We'll email you when they're processed."
    redirect_to root_path
  end

  def on_verification_failure
    render_wizard
  end
end
