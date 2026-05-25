# frozen_string_literal: true

module ImageDescriptionProviders
  class Configuration
    attr_reader :setting, :provider_override, :openai_base_url_override, :openai_model_override

    def self.current
      new(DescriptionProviderSetting.current)
    end

    def self.from_job_options(options)
      new(
        DescriptionProviderSetting.current,
        provider: options.fetch("provider"),
        openai_base_url: options["openai_base_url"],
        openai_model: options["openai_model"]
      )
    end

    def initialize(setting, provider: nil, openai_base_url: nil, openai_model: nil)
      @setting = setting
      @provider_override = provider
      @openai_base_url_override = openai_base_url
      @openai_model_override = openai_model
    end

    def provider
      return provider_override if provider_override.present?

      ENV["IMAGE_DESCRIPTION_PROVIDER"].presence&.downcase || setting.provider
    end

    def provider_env_override?
      ENV["IMAGE_DESCRIPTION_PROVIDER"].present?
    end

    def openai_base_url
      return openai_base_url_override if openai_base_url_override.present?

      ENV["OPENAI_API_BASE_URL"].presence || setting.openai_base_url || DescriptionProviderSetting::DEFAULT_OPENAI_BASE_URL
    end

    def openai_model
      return openai_model_override if openai_model_override.present?

      ENV["OPENAI_VISION_MODEL"].presence || setting.openai_model || DescriptionProviderSetting::DEFAULT_OPENAI_MODEL
    end

    def openai_api_key
      ENV["OPENAI_API_KEY"].presence || setting.openai_api_key
    end

    def openai_env_key?
      ENV["OPENAI_API_KEY"].present?
    end

    def openai_base_url_env_override?
      ENV["OPENAI_API_BASE_URL"].present?
    end

    def openai_model_env_override?
      ENV["OPENAI_VISION_MODEL"].present?
    end

    def openai_runtime_key_source
      return "Environment" if openai_env_key?
      return "Saved key" if setting.saved_openai_api_key?

      "Missing"
    end

    def job_options
      {
        "provider" => provider,
        "openai_base_url" => openai_base_url,
        "openai_model" => openai_model
      }
    end
  end
end
