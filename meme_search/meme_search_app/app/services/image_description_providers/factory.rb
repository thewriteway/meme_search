# frozen_string_literal: true

module ImageDescriptionProviders
  class Factory
    def self.build(configuration = Configuration.current)
      case configuration.provider.to_s.downcase
      when "openai"
        OpenaiProvider.new(configuration)
      else
        LocalProvider.new
      end
    end
  end
end
