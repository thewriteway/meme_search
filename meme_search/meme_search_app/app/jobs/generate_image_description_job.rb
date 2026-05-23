# frozen_string_literal: true

class GenerateImageDescriptionJob < ApplicationJob
  queue_as :default

  def perform(image_core_id)
    image_core = ImageCore.find_by(id: image_core_id)
    return unless image_core
    return unless image_core.in_queue?

    ImageDescriptionProviders::Factory.build.generate(image_core)
  end
end
