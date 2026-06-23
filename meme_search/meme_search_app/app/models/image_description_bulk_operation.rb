# frozen_string_literal: true

class ImageDescriptionBulkOperation < ApplicationRecord
  has_many :image_description_generation_attempts, dependent: :nullify
  has_many :image_cores, through: :image_description_generation_attempts

  enum :status, {
    active: 0,
    completed: 1,
    canceled: 2
  }

  validates :provider, presence: true, inclusion: { in: %w[local openai] }
  validates :total_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :started_at, presence: true

  scope :current_first, -> { active.order(created_at: :desc, id: :desc) }

  def self.current
    current_first.first
  end

  def status_snapshot
    operation_images = image_cores
    status_counts = {
      not_started: operation_images.where(status: ImageCore.statuses[:not_started]).count,
      in_queue: operation_images.where(status: ImageCore.statuses[:in_queue]).count,
      processing: operation_images.where(status: ImageCore.statuses[:processing]).count,
      done: operation_images.where(status: ImageCore.statuses[:done]).count,
      failed: operation_images.where(status: ImageCore.statuses[:failed]).count
    }
    active_count = status_counts[:in_queue] + status_counts[:processing]
    complete = active_count.zero? && status_counts[:not_started].zero?
    complete = true if total_count.zero?

    {
      status_counts: status_counts,
      total: total_count,
      is_complete: complete,
      started_at: started_at.to_i
    }
  end

  def mark_completed_if_finished!
    snapshot = status_snapshot
    update!(status: :completed, completed_at: Time.current) if snapshot[:is_complete] && active?
    snapshot
  end

  def cancel!
    update!(status: :canceled, canceled_at: Time.current, completed_at: Time.current)
  end
end
