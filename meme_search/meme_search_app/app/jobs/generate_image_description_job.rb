# frozen_string_literal: true

class GenerateImageDescriptionJob < ApplicationJob
  queue_as :default

  def perform(image_core_id, provider_options = nil, attempt_id = nil)
    image_core = ImageCore.find_by(id: image_core_id)
    return unless image_core
    return unless image_core.in_queue?
    attempt = ImageDescriptionGenerationAttempt.find_by(id: attempt_id)
    return unless attempt&.image_core_id == image_core.id
    return unless attempt.active_for_image?

    configuration =
      if provider_options.present?
        ImageDescriptionProviders::Configuration.from_job_options(provider_options)
      else
        ImageDescriptionProviders::Configuration.current
      end

    ImageDescriptionProviders::Factory.build(configuration).generate(image_core, attempt: attempt)
  end
end
