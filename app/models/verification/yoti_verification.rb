class Verification::YotiVerification < Verification
  after_create_commit :check_for_resemblances

  aasm column: :status, timestamps: true, whiny_transitions: true do
    state :pending, initial: true
    state :approved
    state :rejected

    event :approve do
      transitions from: :pending, to: :approved
    end

    event :mark_as_rejected do
      transitions from: :pending, to: :rejected

      before do |reason, details = nil|
        self.rejection_reason = reason
        self.rejection_reason_details = details
        self.fatal = fatal_rejection_reason?(reason)
      end

      after do
        if fatal_rejection?
          VerificationMailer.rejected_permanently(self).deliver_later
          Slack::NotifyGuardiansJob.perform_later(self.identity)
        else
          VerificationMailer.rejected_amicably(self).deliver_later
        end
      end
    end
  end

  enum :rejection_reason, {
    # Retryable
    yoti_expired: "yoti_expired",
    yoti_needs_retry: "yoti_needs_retry",
    other: "other",
    # Fatal
    yoti_declined: "yoti_declined",
    duplicate: "duplicate",
    under_13: "under_13"
  }

  RETRYABLE_REJECTION_REASONS = %w[yoti_expired yoti_needs_retry other].freeze
  FATAL_REJECTION_REASONS = %w[yoti_declined duplicate under_13].freeze

  REJECTION_REASON_NAMES = {
    "yoti_expired" => "Verification session expired",
    "yoti_needs_retry" => "Verification needs to be retried",
    "other" => "Other issue",
    "yoti_declined" => "ID verification was declined",
    "duplicate" => "This identity is a duplicate of another identity",
    "under_13" => "Submitter is under 13 years old"
  }.freeze

  validates :yoti_session_id, presence: true
  validates :rejection_reason, presence: true, if: :rejected?
  validate :rejection_reason_details_present_when_reason_other

  def document_type
    "Yoti (Automated)"
  end

  def rejection_reason_name
    REJECTION_REASON_NAMES[rejection_reason] || rejection_reason
  end

  private

  def fatal_rejection_reason?(reason)
    return false if reason.blank?

    super(reason) || FATAL_REJECTION_REASONS.include?(reason.to_s)
  end

  def rejection_reason_details_present_when_reason_other
    if rejection_reason == "other" && rejection_reason_details.blank?
      errors.add(:rejection_reason_details, "must be provided when rejection reason is 'other'")
    end
  end

  def check_for_resemblances
    Identity::NoticeResemblancesJob.perform_later(identity)
  end
end
