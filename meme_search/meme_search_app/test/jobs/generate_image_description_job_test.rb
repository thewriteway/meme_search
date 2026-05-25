# frozen_string_literal: true

require "test_helper"

class GenerateImageDescriptionJobTest < ActiveJob::TestCase
  test "generates description for an existing image" do
    image_core = image_cores(:one)
    image_core.update!(status: :in_queue)
    attempt = image_core.start_description_generation_attempt!(provider: "openai")
    generated_with = nil
    provider = Object.new
    provider.define_singleton_method(:generate) do |received_image_core, attempt:|
      generated_with = [ received_image_core, attempt ]
      ImageDescriptionProviders::Result.new(success: true, message: "Generated description.", queued: false)
    end

    ImageDescriptionProviders::Factory.stub(:build, ->(_configuration) { provider }) do
      GenerateImageDescriptionJob.perform_now(image_core.id, nil, attempt.id)
    end

    assert_equal [ image_core, attempt ], generated_with
  end

  test "uses provider settings pinned when the job was enqueued" do
    image_core = image_cores(:one)
    image_core.update!(status: :in_queue)
    attempt = image_core.start_description_generation_attempt!(provider: "openai")
    generated_attempt = nil
    provider = Object.new
    provider.define_singleton_method(:generate) do |_received_image_core, attempt:|
      generated_attempt = attempt
      ImageDescriptionProviders::Result.new(success: true, message: "Generated description.", queued: false)
    end
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
      GenerateImageDescriptionJob.perform_now(image_core.id, provider_options, attempt.id)
    end

    assert_equal attempt, generated_attempt
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
    attempt = image_core.start_description_generation_attempt!(provider: "openai")

    ImageDescriptionProviders::Factory.stub(:build, -> { flunk "provider should not be built for unqueued image" }) do
      assert_nothing_raised do
        GenerateImageDescriptionJob.perform_now(image_core.id, nil, attempt.id)
      end
    end
  end

  test "does nothing when attempt was canceled" do
    image_core = image_cores(:one)
    image_core.update!(status: :in_queue)
    attempt = image_core.start_description_generation_attempt!(provider: "openai")
    attempt.cancel!

    ImageDescriptionProviders::Factory.stub(:build, -> { flunk "provider should not be built for canceled attempt" }) do
      assert_nothing_raised do
        GenerateImageDescriptionJob.perform_now(image_core.id, nil, attempt.id)
      end
    end
  end

  test "does nothing when attempt belongs to another image" do
    image_core = image_cores(:one)
    other_image = image_cores(:two)
    image_core.update!(status: :in_queue)
    attempt = other_image.start_description_generation_attempt!(provider: "openai")

    ImageDescriptionProviders::Factory.stub(:build, -> { flunk "provider should not be built for mismatched attempt" }) do
      assert_nothing_raised do
        GenerateImageDescriptionJob.perform_now(image_core.id, nil, attempt.id)
      end
    end
  end
end
