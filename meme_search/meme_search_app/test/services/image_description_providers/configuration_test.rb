# frozen_string_literal: true

require "test_helper"

class ImageDescriptionProvidersConfigurationTest < ActiveSupport::TestCase
  def setup
    @setting = DescriptionProviderSetting.current
    @setting.update!(
      provider: "openai",
      openai_base_url: "http://saved.example/v1",
      openai_model: "gpt-4.1-mini"
    )
    @setting.openai_api_key = "sk-saved-1234"
    @setting.save!
  end

  test "provider uses saved setting when env is absent" do
    with_env("IMAGE_DESCRIPTION_PROVIDER" => nil) do
      config = ImageDescriptionProviders::Configuration.current

      assert_equal "openai", config.provider
      assert_not config.provider_env_override?
    end
  end

  test "provider env var overrides saved setting" do
    with_env("IMAGE_DESCRIPTION_PROVIDER" => "local") do
      config = ImageDescriptionProviders::Configuration.current

      assert_equal "local", config.provider
      assert config.provider_env_override?
    end
  end

  test "openai values use saved settings when env is absent" do
    with_env(
      "OPENAI_API_BASE_URL" => nil,
      "OPENAI_VISION_MODEL" => nil,
      "OPENAI_API_KEY" => nil
    ) do
      config = ImageDescriptionProviders::Configuration.current

      assert_equal "http://saved.example/v1", config.openai_base_url
      assert_equal "gpt-4.1-mini", config.openai_model
      assert_equal "sk-saved-1234", config.openai_api_key
      assert_equal "Saved key", config.openai_runtime_key_source
    end
  end

  test "openai env values override saved settings" do
    with_env(
      "OPENAI_API_BASE_URL" => "http://env.example/v1",
      "OPENAI_VISION_MODEL" => "gpt-4.1",
      "OPENAI_API_KEY" => "sk-env-1234"
    ) do
      config = ImageDescriptionProviders::Configuration.current

      assert_equal "http://env.example/v1", config.openai_base_url
      assert_equal "gpt-4.1", config.openai_model
      assert_equal "sk-env-1234", config.openai_api_key
      assert_equal "Environment", config.openai_runtime_key_source
      assert config.openai_env_key?
      assert config.openai_base_url_env_override?
      assert config.openai_model_env_override?
    end
  end

  test "missing openai key reports missing source" do
    @setting.clear_openai_api_key
    @setting.save!

    with_env("OPENAI_API_KEY" => nil) do
      config = ImageDescriptionProviders::Configuration.current

      assert_nil config.openai_api_key
      assert_equal "Missing", config.openai_runtime_key_source
    end
  end

  test "job options pin provider and openai runtime values without serializing api key" do
    with_env(
      "IMAGE_DESCRIPTION_PROVIDER" => "openai",
      "OPENAI_API_BASE_URL" => "http://env.example/v1",
      "OPENAI_VISION_MODEL" => "gpt-4.1",
      "OPENAI_API_KEY" => "sk-env-1234"
    ) do
      options = ImageDescriptionProviders::Configuration.current.job_options

      assert_equal(
        {
          "provider" => "openai",
          "openai_base_url" => "http://env.example/v1",
          "openai_model" => "gpt-4.1"
        },
        options
      )
      assert_not_includes options.keys, "openai_api_key"
    end
  end

  test "job options override later provider and model changes while resolving current key" do
    options = {
      "provider" => "openai",
      "openai_base_url" => "http://queued.example/v1",
      "openai_model" => "gpt-queued"
    }

    with_env(
      "IMAGE_DESCRIPTION_PROVIDER" => "local",
      "OPENAI_API_BASE_URL" => "http://env.example/v1",
      "OPENAI_VISION_MODEL" => "gpt-env",
      "OPENAI_API_KEY" => "sk-env-1234"
    ) do
      config = ImageDescriptionProviders::Configuration.from_job_options(options)

      assert_equal "openai", config.provider
      assert_equal "http://queued.example/v1", config.openai_base_url
      assert_equal "gpt-queued", config.openai_model
      assert_equal "sk-env-1234", config.openai_api_key
    end
  end

  private

    def with_env(values)
      old_values = values.keys.to_h { |key| [ key, ENV[key] ] }
      values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      yield
    ensure
      old_values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
end
