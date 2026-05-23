# frozen_string_literal: true

module ImageDescriptionProviders
  class Configuration
    attr_reader :setting

    def self.current
      new(DescriptionProviderSetting.current)
    end

    def initialize(setting)
      @setting = setting
    end

    def provider
      ENV["IMAGE_DESCRIPTION_PROVIDER"].presence&.downcase || setting.provider
    end

    def provider_env_override?
      ENV["IMAGE_DESCRIPTION_PROVIDER"].present?
    end

    def openai_base_url
      ENV["OPENAI_API_BASE_URL"].presence || setting.openai_base_url || DescriptionProviderSetting::DEFAULT_OPENAI_BASE_URL
    end

    def openai_model
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
  end
end
