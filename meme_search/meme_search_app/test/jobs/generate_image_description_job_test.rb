# frozen_string_literal: true

require "test_helper"

class GenerateImageDescriptionJobTest < ActiveJob::TestCase
  test "generates description for an existing image" do
    image_core = image_cores(:one)
    image_core.update!(status: :in_queue)
    provider = Minitest::Mock.new
    provider.expect(:generate, ImageDescriptionProviders::Result.new(success: true, message: "Generated description.", queued: false), [ image_core ])

    ImageDescriptionProviders::Factory.stub(:build, provider) do
      GenerateImageDescriptionJob.perform_now(image_core.id)
    end

    provider.verify
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
