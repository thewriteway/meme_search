# frozen_string_literal: true

module ImageDescriptionProviders
  class Factory
    def self.build(configuration = Configuration.current)
      case configuration.provider.to_s.downcase
      when "local", ""
        LocalProvider.new
      when "openai"
        OpenaiProvider.new(configuration)
      else
        raise ArgumentError, "Unknown image description provider: #{configuration.provider}"
      end
    end
  end
end
