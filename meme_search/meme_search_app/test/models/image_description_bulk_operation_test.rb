# frozen_string_literal: true

require "test_helper"

class ImageDescriptionBulkOperationTest < ActiveSupport::TestCase
  test "status snapshot counts only attempts attached to operation" do
    operation = ImageDescriptionBulkOperation.create!(
      provider: "local",
      provider_queued: true,
      total_count: 2,
      started_at: Time.current
    )
    included = image_cores(:one)
    included.update!(status: :in_queue)
    included.start_description_generation_attempt!(provider: "local", bulk_operation: operation)

    outside = image_cores(:two)
    outside.update!(status: :done)
    outside.start_description_generation_attempt!(provider: "local")

    snapshot = operation.status_snapshot

    assert_equal 2, snapshot[:total]
    assert_equal 1, snapshot[:status_counts][:in_queue]
    assert_equal 0, snapshot[:status_counts][:done]
    assert_equal false, snapshot[:is_complete]
  end

  test "completed operation is removed from current active operation" do
    operation = ImageDescriptionBulkOperation.create!(
      provider: "openai",
      provider_queued: false,
      total_count: 0,
      started_at: Time.current
    )

    snapshot = operation.mark_completed_if_finished!

    assert_equal true, snapshot[:is_complete]
    assert_equal "completed", operation.reload.status
    assert_nil ImageDescriptionBulkOperation.current
  end
end
