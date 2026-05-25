# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module ImageDescriptionProviders
  class LocalProvider
    ADD_JOB_URL = "http://image_to_text_generator:8000/add_job"
    READ_TIMEOUT = 35

    def name
      "local"
    end

    def queued_provider?
      true
    end

    def generate(image_core)
      image_core.update(status: :in_queue)

      current_model = ImageToText.find_by(current: true)
      uri = URI(ADD_JOB_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = {
        image_core_id: image_core.id,
        image_path: "#{image_core.image_path.name}/#{image_core.name}",
        model: current_model&.name
      }.to_json

      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        Result.new(success: true, message: nil, queued: true)
      else
        image_core.update(status: :failed)
        Result.new(success: false, message: "Cannot generate description, your image to text genertaor is offline!", queued: true)
      end
    rescue StandardError => e
      Rails.logger.error "Failed to queue image #{image_core.id}: #{e.class}: #{e.message}"
      image_core.update(status: :failed)
      Result.new(success: false, message: "Cannot generate description, your image to text genertaor is offline!", queued: true)
    end
  end
end
