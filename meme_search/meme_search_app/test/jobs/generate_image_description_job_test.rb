# frozen_string_literal: true

require "test_helper"

class GenerateImageDescriptionJobTest < ActiveJob::TestCase
  test "generates description for an existing image" do
    image_core = image_cores(:one)
    image_core.update!(status: :in_queue)
    provider = Minitest::Mock.new
    provider.expect(:generate, ImageDescriptionProviders::Result.new(success: true, message: "Generated description.", queued: false), [ image_core ])

    ImageDescriptionProviders::Factory.stub(:build, ->(_configuration) { provider }) do
      GenerateImageDescriptionJob.perform_now(image_core.id)
    end

    assert_mock provider
  end

  test "uses provider settings pinned when the job was enqueued" do
    image_core = image_cores(:one)
    image_core.update!(status: :in_queue)
    provider = Minitest::Mock.new
    provider.expect(:generate, ImageDescriptionProviders::Result.new(success: true, message: "Generated description.", queued: false), [ image_core ])
    provider_options = {
      "provider" => "openai",
      "openai_base_url" => "http://queued.example/v1",
      "openai_model" => "gpt-queued"
    }

    ImageDescriptionProviders::Factory.stub(:build, ->(configuration) {
      assert_equal "openai", configuration.provider
      assert_equal "http://queued.example/v1", configuration.openai_base_url
      assert_equal "gpt-queued", configuration.openai_model
      provider
    }) do
      GenerateImageDescriptionJob.perform_now(image_core.id, provider_options)
    end

    assert_mock provider
  end

  test "does nothing when image no longer exists" do
    ImageDescriptionProviders::Factory.stub(:build, -> { flunk "provider should not be built for missing image" }) do
      assert_nothing_raised do
        GenerateImageDescriptionJob.perform_now(-1)
      end
    end
  end

  test "does nothing when image is no longer queued" do
    image_core = image_cores(:one)
    image_core.update!(status: :not_started)

    ImageDescriptionProviders::Factory.stub(:build, -> { flunk "provider should not be built for unqueued image" }) do
      assert_nothing_raised do
        GenerateImageDescriptionJob.perform_now(image_core.id)
      end
    end
  end
end
