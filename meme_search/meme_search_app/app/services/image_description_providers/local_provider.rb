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

    def generate(image_core, bulk_operation: nil)
      current_model = ImageToText.find_by(current: true)
      attempt = image_core.start_description_generation_attempt!(
        provider: name,
        provider_settings: { model: current_model&.name }.compact,
        bulk_operation: bulk_operation
      )
      image_core.update!(status: :in_queue)

      uri = URI(ADD_JOB_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = {
        image_core_id: image_core.id,
        image_path: "#{image_core.image_path.name}/#{image_core.name}",
        model: current_model&.name,
        attempt_id: attempt.id,
        callback_token: attempt.callback_token
      }.to_json

      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        Result.new(success: true, message: nil, queued: true)
      else
        attempt.fail_with_error!("Local image to text generator returned #{response.code} #{response.message}.")
        Result.new(success: false, message: "Cannot generate description, your image to text genertaor is offline!", queued: true)
      end
    rescue StandardError => e
      Rails.logger.error "Failed to queue image #{image_core.id}: #{e.class}: #{e.message}"
      attempt&.fail_with_error!(e.message)
      image_core.update(status: :failed) unless attempt
      Result.new(success: false, message: "Cannot generate description, your image to text genertaor is offline!", queued: true)
    end
  end
end
