# frozen_string_literal: true

require "test_helper"
require "fileutils"

class OpenaiDescriptionGenerationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    reset_provider_setting
    @image_dir = Rails.root.join("public", "memes", "openai_integration_path")
    FileUtils.mkdir_p(@image_dir)
    @image_path = ImagePath.create!(name: "openai_integration_path")
    @image_core = ImageCore.create!(name: "integration.jpg", image_path: @image_path, status: :not_started)
    File.binwrite(@image_dir.join(@image_core.name), "fake image bytes")
  end

  def teardown
    FileUtils.rm_rf(@image_dir) if @image_dir
    reset_provider_setting
    WebMock.reset!
  end

  test "saved OpenAI-compatible settings generate a description through the queued job without real network" do
    api_key = "sk-integration-openai-1234"
    generated_description = "A mocked cloud vision description."
    captured_request_body = nil

    with_clean_openai_env do
      post save_openai_settings_settings_image_to_texts_path, params: {
        description_provider_setting: {
          openai_base_url: "http://openai.test/v1",
          openai_model: "gpt-4.1",
          openai_api_key: api_key
        }
      }
      assert_redirected_to settings_image_to_texts_path(provider_tab: "openai")

      stub = stub_request(:post, "http://openai.test/v1/chat/completions")
        .with(headers: { "Authorization" => "Bearer #{api_key}" }) do |request|
          captured_request_body = JSON.parse(request.body)
          true
        end
        .to_return(
          status: 200,
          body: { choices: [ { message: { content: generated_description } } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      assert_difference -> { ImageDescriptionGenerationAttempt.count }, 1 do
        assert_enqueued_jobs 1, only: GenerateImageDescriptionJob do
          post generate_description_image_core_path(@image_core)
        end
      end

      assert_response :redirect
      attempt = @image_core.reload.active_description_generation_attempt
      assert_equal "queued", attempt.status
      assert_equal "openai", attempt.provider
      assert_equal(
        {
          "provider" => "openai",
          "openai_base_url" => "http://openai.test/v1",
          "openai_model" => "gpt-4.1"
        },
        attempt.provider_settings
      )
      refute_includes enqueued_jobs.last.to_s, api_key

      perform_enqueued_jobs

      assert_requested stub, times: 1
      assert_equal "gpt-4.1", captured_request_body.fetch("model")
      image_content = captured_request_body.dig("messages", 0, "content").find { |part| part["type"] == "image_url" }
      assert_match %r{\Adata:image/jpeg;base64,}, image_content.dig("image_url", "url")
    end

    @image_core.reload
    assert_equal generated_description, @image_core.description
    assert_equal "done", @image_core.status

    attempt = @image_core.image_description_generation_attempts.order(:created_at).last
    assert_equal "succeeded", attempt.status
    refute_includes attempt.provider_settings.to_s, api_key
    assert_not_requested :post, "https://api.openai.com/v1/chat/completions"
  end

  private

    def with_clean_openai_env
      keys = %w[
        IMAGE_DESCRIPTION_PROVIDER
        OPENAI_API_BASE_URL
        OPENAI_API_KEY
        OPENAI_VISION_MODEL
      ]
      old_values = keys.index_with { |key| ENV[key] }
      keys.each { |key| ENV.delete(key) }
      yield
    ensure
      old_values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    def reset_provider_setting
      DescriptionProviderSetting.delete_all
    end
end
