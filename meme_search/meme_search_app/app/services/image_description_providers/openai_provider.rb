# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "uri"

module ImageDescriptionProviders
  class OpenaiProvider
    DEFAULT_BASE_URL = "https://api.openai.com/v1"
    DEFAULT_MODEL = "gpt-4o-mini"
    PROMPT = "Describe this meme for semantic search. Include visible text, objects, people, setting, and the joke or sentiment. Keep it concise."
    TEST_IMAGE_DATA_URL = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAA+UlEQVR42u3aQQ7CIBCF4XcJz9K1R/DeXqdp0pUujYl0GBh5DC9hyeL/YqOVAftxTr0ggAACCCAANeB83mYCvHMtiw5g7I6QYFR6LwbGprczQFLvNoCn3mcAVb3DALb6WgMI66sM4Ky3G0BbbzQsABhYbzF0A2z3R1WWfX8TwJjyubrvLxuWB3zVXDbV7m8C2J/m6E+gYBAg/lvoT4BRvwYC0AKo6gsGPUICCCDAr1c0y4oFlA3uaAcm5HXal0IKcD/Z4YCF/tTzAnSwRQCY/mw0w+l0hvlAhglNhhlZhillhjlxhkl9krsSSW6r5LkvpCtnAgggwGqAFzX/iQwCblWQAAAAAElFTkSuQmCC"
    TEST_PROMPT = "Reply with ok if you can inspect this image."
    UNSUPPORTED_TEST_RESPONSE_MESSAGE = "OpenAI connection test returned an unsupported response."
    MAX_COMPLETION_TOKENS = 160

    def initialize(configuration = Configuration.current)
      @configuration = configuration
    end

    def name
      "openai"
    end

    def queued_provider?
      false
    end

    def test_connection
      if api_key.blank?
        return Result.new(
          success: false,
          message: "OpenAI API key is required. Add one in Settings or set OPENAI_API_KEY.",
          queued: false
        )
      end

      uri = URI.join(base_url, "chat/completions")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 30

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "application/json"
      request.body = {
        model: model,
        max_tokens: 5,
        messages: [
          {
            role: "user",
            content: [
              { type: "text", text: TEST_PROMPT },
              { type: "image_url", image_url: { url: TEST_IMAGE_DATA_URL } }
            ]
          }
        ]
      }.to_json

      response = http.request(request)
      if response.is_a?(Net::HTTPSuccess)
        content = JSON.parse(response.body).dig("choices", 0, "message", "content").to_s.strip
        return Result.new(success: true, message: "OpenAI connection test passed.", queued: false) if content.present?

        return Result.new(success: false, message: UNSUPPORTED_TEST_RESPONSE_MESSAGE, queued: false)
      end

      Result.new(success: false, message: "OpenAI vision API error: #{response.code} #{response.message}", queued: false)
    rescue JSON::ParserError
      Result.new(success: false, message: UNSUPPORTED_TEST_RESPONSE_MESSAGE, queued: false)
    rescue Net::OpenTimeout, Net::ReadTimeout
      Result.new(success: false, message: "OpenAI vision API request timed out.", queued: false)
    rescue StandardError => e
      Result.new(success: false, message: e.message, queued: false)
    end

    def generate(image_core, attempt: nil)
      attempt ||= create_direct_attempt(image_core)
      return stale_attempt_result unless attempt&.active_for_image?
      return stale_attempt_result unless attempt.transition_to_processing!

      image_core.reload
      broadcast_status(image_core)

      unless api_key.present?
        return fail_image(image_core, attempt, "OpenAI API key is required. Add one in Settings or set OPENAI_API_KEY.")
      end

      description = ImageCore.normalize_description(request_description(image_core))
      if description.blank?
        return fail_image(image_core, attempt, "OpenAI vision API returned an unsupported response.")
      end

      save_description(image_core, attempt, description)
      Result.new(success: true, message: "Generated description.", queued: false)
    rescue Net::OpenTimeout, Net::ReadTimeout
      fail_image(image_core, attempt, "OpenAI vision API request timed out.")
    rescue StandardError => e
      Rails.logger.error "OpenAI image description failed for image #{image_core.id}: #{e.class}: #{e.message}"
      fail_image(image_core, attempt, e.message)
    end

    private

      attr_reader :configuration

      def request_description(image_core)
        uri = URI.join(base_url, "chat/completions")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 60

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{api_key}"
        request["Content-Type"] = "application/json"
        request.body = request_body(image_core).to_json

        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          raise "OpenAI vision API error: #{response.code} #{response.message}"
        end

        JSON.parse(response.body).dig("choices", 0, "message", "content").to_s.strip
      rescue JSON::ParserError
        raise "OpenAI vision API returned invalid JSON."
      end

      def request_body(image_core)
        {
          model: model,
          max_tokens: MAX_COMPLETION_TOKENS,
          messages: [
            {
              role: "user",
              content: [
                { type: "text", text: PROMPT },
                { type: "image_url", image_url: { url: data_uri(image_core) } }
              ]
            }
          ]
        }
      end

      def data_uri(image_core)
        path = Rails.root.join("public", "memes", image_core.image_path.name, image_core.name)
        raise "Image file not found: #{path}" unless File.file?(path)

        return first_gif_frame_data_uri(path) if File.extname(path).casecmp(".gif").zero?

        "data:#{mime_type(path)};base64,#{Base64.strict_encode64(File.binread(path))}"
      end

      def first_gif_frame_data_uri(path)
        require "image_processing/vips"

        first_frame = ImageProcessing::Vips
          .source(path.to_s)
          .loader(page: 0, n: 1)
          .convert("png")
          .call

        "data:image/png;base64,#{Base64.strict_encode64(File.binread(first_frame.path))}"
      ensure
        first_frame&.close!
      end

      def mime_type(path)
        Marcel::MimeType.for(Pathname.new(path.to_s), name: File.basename(path)) || mime_type_from_extension(path)
      rescue StandardError
        mime_type_from_extension(path)
      end

      def mime_type_from_extension(path)
        case File.extname(path).downcase
        when ".jpg", ".jpeg" then "image/jpeg"
        when ".png" then "image/png"
        when ".webp" then "image/webp"
        when ".gif" then "image/gif"
        else "application/octet-stream"
        end
      end

      def create_direct_attempt(image_core)
        attempt = image_core.start_description_generation_attempt!(
          provider: name,
          provider_settings: configuration.job_options
        )
        image_core.update!(status: :in_queue)
        attempt
      end

      def stale_attempt_result
        Result.new(success: false, message: "Image description generation attempt is no longer active.", queued: false)
      end

      def save_description(image_core, attempt, description)
        return stale_attempt_result unless attempt.succeed_with_description!(description)

        image_core.reload
        div_id = "description-image-core-id-#{image_core.id}"
        ActionCable.server.broadcast "image_description_channel", { div_id: div_id, description: description }
        broadcast_status(image_core)
        image_core.refresh_description_embeddings
      end

      def fail_image(image_core, attempt, message)
        return stale_attempt_result unless attempt&.fail_with_error!(message)

        image_core.reload
        broadcast_status(image_core)
        Result.new(success: false, message: message, queued: false)
      end

      def broadcast_status(image_core)
        div_id = "status-image-core-id-#{image_core.id}"
        status_html = ApplicationController.renderer.render(
          partial: "image_cores/generate_status",
          locals: { img_id: image_core.id, div_id: div_id, status: image_core.status }
        )
        ActionCable.server.broadcast "image_status_channel", { div_id: div_id, status_html: status_html }
      end

      def base_url
        configuration.openai_base_url.to_s.chomp("/") + "/"
      end

      def api_key
        configuration.openai_api_key.to_s
      end

      def model
        configuration.openai_model.presence || DEFAULT_MODEL
      end
  end
end
