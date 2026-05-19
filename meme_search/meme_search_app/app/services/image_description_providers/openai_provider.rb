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

    def generate(image_core)
      image_core.update(status: :processing)

      unless api_key.present?
        return fail_image(image_core, "OPENAI_API_KEY is required for OpenAI image description generation.")
      end

      description = request_description(image_core)
      if description.blank?
        return fail_image(image_core, "OpenAI vision API returned an unsupported response.")
      end

      save_description(image_core, description)
      Result.new(success: true, message: "Generated description.", queued: false)
    rescue Net::OpenTimeout, Net::ReadTimeout
      fail_image(image_core, "OpenAI vision API request timed out.")
    rescue StandardError => e
      Rails.logger.error "OpenAI image description failed for image #{image_core.id}: #{e.class}: #{e.message}"
      fail_image(image_core, e.message)
    end

    private

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

        "data:#{mime_type(path)};base64,#{Base64.strict_encode64(File.binread(path))}"
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

      def save_description(image_core, description)
        image_core.update!(description: description, status: :done)
        div_id = "description-image-core-id-#{image_core.id}"
        ActionCable.server.broadcast "image_description_channel", { div_id: div_id, description: description }
        image_core.refresh_description_embeddings
      end

      def fail_image(image_core, message)
        image_core.update(status: :failed)
        Result.new(success: false, message: message, queued: false)
      end

      def base_url
        (ENV["OPENAI_API_BASE_URL"].presence || DEFAULT_BASE_URL).to_s.chomp("/") + "/"
      end

      def api_key
        ENV["OPENAI_API_KEY"].to_s
      end

      def model
        ENV["OPENAI_VISION_MODEL"].presence || DEFAULT_MODEL
      end
  end
end
