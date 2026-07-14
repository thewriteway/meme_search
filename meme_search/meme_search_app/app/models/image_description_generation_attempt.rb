# frozen_string_literal: true

class ImageDescriptionGenerationAttempt < ApplicationRecord
  belongs_to :image_core
  belongs_to :image_description_bulk_operation, optional: true

  enum :status, {
    queued: 0,
    processing: 1,
    succeeded: 2,
    failed: 3,
    canceled: 4
  }

  ACTIVE_STATUSES = %w[queued processing].freeze

  validates :provider, presence: true, inclusion: { in: %w[local openai] }
  validates :status, presence: true

  scope :active, -> { where(status: ACTIVE_STATUSES.map { |status| statuses.fetch(status) }) }

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  def active_for_image?
    image_core_id.present? && active? && self.class.active.where(id: id, image_core_id: image_core_id).exists?
  end

  def callback_token
    self.class.callback_verifier.generate({
      "attempt_id" => id,
      "image_core_id" => image_core_id
    })
  end

  def self.find_verified_callback_attempt(attempt_id:, image_core_id:, callback_token:)
    return nil if attempt_id.blank? || image_core_id.blank? || callback_token.blank?

    payload = callback_verifier.verify(callback_token)
    return nil unless payload.fetch("attempt_id").to_i == attempt_id.to_i
    return nil unless payload.fetch("image_core_id").to_i == image_core_id.to_i

    find_by(id: attempt_id, image_core_id: image_core_id)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, KeyError
    nil
  end

  def self.callback_verifier
    Rails.application.message_verifier(:image_description_generation_callback)
  end

  def mark_queued!
    guarded_update do |attempt, image|
      image.update!(status: :in_queue) unless image.in_queue?
      attempt.update!(status: :queued) unless attempt.queued?
    end
  end

  def transition_to_processing!
    guarded_update do |attempt, image|
      image.update!(status: :processing) unless image.processing?
      attempt.update!(
        status: :processing,
        started_at: attempt.started_at || Time.current
      )
    end
  end

  def succeed_with_description!(description)
    guarded_update do |attempt, image|
      image.update!(description: ImageCore.normalize_description(description), status: :done)
      attempt.update!(status: :succeeded, completed_at: Time.current)
    end
  end

  def fail_with_error!(message)
    guarded_update do |attempt, image|
      image.update!(status: :failed)
      attempt.update!(status: :failed, error_message: message, completed_at: Time.current)
    end
  end

  def cancel!
    guarded_update do |attempt, image|
      image.update!(status: :not_started) if image.in_queue? || image.removing?
      attempt.update!(status: :canceled, canceled_at: Time.current, completed_at: Time.current)
    end
  end

  private

    def guarded_update
      self.class.transaction do
        locked_attempt = self.class.lock.find_by(id: id)
        return false unless locked_attempt&.active?

        locked_image = ImageCore.lock.find_by(id: locked_attempt.image_core_id)
        return false unless locked_image&.active_description_generation_attempt&.id == locked_attempt.id

        yield locked_attempt, locked_image
      end

      reload
      true
    end
end
