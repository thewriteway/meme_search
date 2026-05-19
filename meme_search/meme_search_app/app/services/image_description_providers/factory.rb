# frozen_string_literal: true

module ImageDescriptionProviders
  class Factory
    def self.build
      case ENV.fetch("IMAGE_DESCRIPTION_PROVIDER", "local").to_s.downcase
      when "openai"
        OpenaiProvider.new
      else
        LocalProvider.new
      end
    end
  end
end
