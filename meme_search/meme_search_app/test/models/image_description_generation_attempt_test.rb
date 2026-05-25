# frozen_string_literal: true

require "test_helper"

class ImageDescriptionGenerationAttemptTest < ActiveSupport::TestCase
  test "image can have only one active attempt" do
    image_core = image_cores(:one)
    image_core.start_description_generation_attempt!(provider: "openai")

    assert_raises ActiveRecord::RecordInvalid do
      image_core.start_description_generation_attempt!(provider: "openai")
    end
  end

  test "canceled attempt is no longer active and cannot save description" do
    image_core = image_cores(:one)
    attempt = image_core.start_description_generation_attempt!(provider: "openai")
    image_core.update!(status: :in_queue)
    attempt.cancel!

    assert_not attempt.reload.active_for_image?
    assert_not attempt.succeed_with_description!("stale description")
    assert_not_equal "stale description", image_core.reload.description
    assert_equal "not_started", image_core.status
  end

  test "active attempt can transition and save description" do
    image_core = image_cores(:one)
    attempt = image_core.start_description_generation_attempt!(provider: "openai")
    image_core.update!(status: :in_queue)

    assert attempt.transition_to_processing!
    assert_equal "processing", attempt.status
    assert_equal "processing", image_core.reload.status

    assert attempt.succeed_with_description!("fresh description")
    assert_equal "succeeded", attempt.status
    assert_equal "fresh description", image_core.reload.description
    assert_equal "done", image_core.status
  end

  test "cancel active attempt resets queued image to not started" do
    image_core = image_cores(:one)
    image_core.start_description_generation_attempt!(provider: "openai")
    image_core.update!(status: :in_queue)

    assert image_core.cancel_active_description_generation_attempt!
    assert_equal "not_started", image_core.reload.status
    assert_equal "canceled", image_core.image_description_generation_attempts.last.status
  end

  test "callback token verifies only matching attempt and image" do
    image_core = image_cores(:one)
    attempt = image_core.start_description_generation_attempt!(provider: "local")
    token = attempt.callback_token

    assert_equal attempt, ImageDescriptionGenerationAttempt.find_verified_callback_attempt(
      attempt_id: attempt.id,
      image_core_id: image_core.id,
      callback_token: token
    )

    assert_nil ImageDescriptionGenerationAttempt.find_verified_callback_attempt(
      attempt_id: attempt.id,
      image_core_id: image_cores(:two).id,
      callback_token: token
    )
    assert_nil ImageDescriptionGenerationAttempt.find_verified_callback_attempt(
      attempt_id: attempt.id,
      image_core_id: image_core.id,
      callback_token: "bad-token"
    )
  end
end
