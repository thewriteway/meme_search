# frozen_string_literal: true

require "test_helper"

class ImageDescriptionProviders::FactoryTest < ActiveSupport::TestCase
  test "builds local provider for local configuration" do
    configuration = ImageDescriptionProviders::Configuration.from_job_options({ "provider" => "local" })

    assert_instance_of ImageDescriptionProviders::LocalProvider, ImageDescriptionProviders::Factory.build(configuration)
  end

  test "builds openai provider for openai configuration" do
    configuration = ImageDescriptionProviders::Configuration.from_job_options({
      "provider" => "openai",
      "openai_base_url" => "http://openai.test/v1",
      "openai_model" => "vision-test"
    })

    assert_instance_of ImageDescriptionProviders::OpenaiProvider, ImageDescriptionProviders::Factory.build(configuration)
  end

  test "unknown provider fails closed" do
    configuration = ImageDescriptionProviders::Configuration.from_job_options({ "provider" => "surprise" })

    assert_raises ArgumentError do
      ImageDescriptionProviders::Factory.build(configuration)
    end
  end
end
