# frozen_string_literal: true

require "test_helper"
require "json"

class ImageDescriptionProviders::LocalProviderTest < ActiveSupport::TestCase
  def setup
    @image_core = image_cores(:one)
    @image_core.update!(status: :not_started)
    ImageToText.create!(
      name: "Test Model",
      resource: "org/test",
      description: "Test",
      current: true
    )
  end

  test "queues local job with signed attempt callback token" do
    stub_request(:post, "http://image_to_text_generator:8000/add_job")
      .to_return(status: 200, body: '{"status":"queued"}', headers: { "Content-Type" => "application/json" })

    result = ImageDescriptionProviders::LocalProvider.new.generate(@image_core)

    assert result.success?
    assert_equal "in_queue", @image_core.reload.status
    attempt = @image_core.active_description_generation_attempt
    assert_equal "local", attempt.provider

    payload = nil
    assert_requested(:post, "http://image_to_text_generator:8000/add_job") do |request|
      payload = JSON.parse(request.body)
    end

    assert_equal @image_core.id, payload.fetch("image_core_id")
    assert_equal attempt.id, payload.fetch("attempt_id")
    assert_equal attempt, ImageDescriptionGenerationAttempt.find_verified_callback_attempt(
      attempt_id: payload.fetch("attempt_id"),
      image_core_id: payload.fetch("image_core_id"),
      callback_token: payload.fetch("callback_token")
    )
  end

  test "failed local queue request fails active attempt" do
    stub_request(:post, "http://image_to_text_generator:8000/add_job")
      .to_return(status: 503, body: '{"error":"offline"}', headers: { "Content-Type" => "application/json" })

    result = ImageDescriptionProviders::LocalProvider.new.generate(@image_core)

    assert_not result.success?
    assert_equal "failed", @image_core.reload.status
    attempt = @image_core.image_description_generation_attempts.last
    assert_equal "failed", attempt.status
    assert_match "503", attempt.error_message
  end
end
