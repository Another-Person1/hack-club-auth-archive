class Yoti::ProcessSessionJob < ApplicationJob
  queue_as :default

  def perform(session_id:)
    session_data = YotiService.instance.get_session(session_id)

    verification = Verification::YotiVerification.find_by(yoti_session_id: session_id)
    return if verification.nil?
    return unless verification.pending?

    update_verification_data(verification, session_data)

    case session_data[:state]
    when "COMPLETED"
      process_completed_session(verification, session_data)
    else
      Rails.logger.info("[Yoti] Session #{session_id} has state: #{session_data[:state]}, skipping")
    end
  rescue YotiService::YotiError => e
    Sentry.capture_exception(e)
    Rails.logger.error("[Yoti] Error processing session #{session_id}: #{e.message}")
  end

  private

  def update_verification_data(verification, session_data)
    birthdate = session_data.dig(:resources, :birthdate)
    age = birthdate.present? ? Identity.calculate_age(Date.parse(birthdate)) : nil

    verification.update!(
      yoti_status: session_data[:state],
      yoti_completed_at: Time.current,
      yoti_verified_age: age
    )
  end

  def process_completed_session(verification, session_data)
    # Check if all checks passed
    checks = session_data[:checks] || []
    all_approved = checks.all? { |c| c[:report] == "APPROVE" }

    unless all_approved
      # Some checks failed
      failed_checks = checks.select { |c| c[:report] != "APPROVE" }
      Rails.logger.info("[Yoti] Session #{verification.yoti_session_id} has failed checks: #{failed_checks.map { |c| c[:type] }.join(', ')}")
      verification.mark_as_rejected!("yoti_declined")
      return
    end

    identity = verification.identity
    age = verification.yoti_verified_age

    # Run resemblance detection first
    ResemblanceNoticerEngine.run(identity)
    identity.reload

    has_resemblances = identity.resemblances.any?

    if age.present? && age < 13
      verification.mark_as_rejected!("under_13")
    elsif age.present? && age.between?(13, 18) && !has_resemblances
      auto_approve(verification, identity)
    elsif age.present? && age.between?(13, 18) && has_resemblances
      hold_for_review(verification)
    elsif age.present? && age > 18
      approve_not_ysws(verification, identity)
    else
      # Edge case: no age data extracted, hold for manual review
      hold_for_review(verification)
    end
  end

  def auto_approve(verification, identity)
    verification.approve!
    verification.update!(auto_approved: true)
    identity.update!(ysws_eligible: true)
    VerificationMailer.approved(verification).deliver_later
    identity.create_activity(:yoti_auto_approved, owner: nil)
  end

  def hold_for_review(verification)
    verification.update!(yoti_status: "COMPLETED_NEEDS_REVIEW")
    # Stays in pending — will appear in admin pending queue
    # Notify via Slack
    Slack::NotifyGuardiansJob.perform_later(verification.identity)
  end

  def approve_not_ysws(verification, identity)
    verification.approve!
    identity.update!(ysws_eligible: false)
    IdentityMailer.approved_but_ysws_ineligible(identity).deliver_later
    Slack::NotifyGuardiansJob.perform_later(identity)
  end
end
