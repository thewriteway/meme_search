# frozen_string_literal: true

require "test_helper"
require "fileutils"

class ImageDescriptionProvidersTest < ActiveSupport::TestCase
  def setup
    @image_core = image_cores(:one)
    @image_file = Rails.root.join("public", "memes", @image_core.image_path.name, @image_core.name)
    FileUtils.mkdir_p(@image_file.dirname)
    File.binwrite(@image_file, "fake image bytes")
  end

  def teardown
    FileUtils.rm_f(@image_file)
    WebMock.reset!
  end

  test "factory defaults to local provider" do
    with_env("IMAGE_DESCRIPTION_PROVIDER" => nil) do
      assert_instance_of ImageDescriptionProviders::LocalProvider, ImageDescriptionProviders::Factory.build
    end
  end

  test "factory selects openai provider" do
    with_env("IMAGE_DESCRIPTION_PROVIDER" => "openai") do
      assert_instance_of ImageDescriptionProviders::OpenaiProvider, ImageDescriptionProviders::Factory.build
    end
  end

  test "openai provider saves description and broadcasts on success" do
    description = "A meme with visible text and a joke."

    with_openai_env do
      stub_request(:post, "http://openai.test/v1/chat/completions")
        .with { |request| openai_request_valid?(request) }
        .to_return(
          status: 200,
          body: { choices: [ { message: { content: description } } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      @image_core.stub(:refresh_description_embeddings, true) do
        ActionCable.server.stub(:broadcast, ->(channel, data) {
          assert_equal "image_description_channel", channel
          assert_equal description, data[:description]
        }) do
          result = ImageDescriptionProviders::OpenaiProvider.new.generate(@image_core)
          assert result.success?
          assert_not result.queued?
        end
      end
    end

    @image_core.reload
    assert_equal description, @image_core.description
    assert_equal "done", @image_core.status
  end

  test "openai provider fails gracefully when api key is missing" do
    with_env(
      "IMAGE_DESCRIPTION_PROVIDER" => "openai",
      "OPENAI_API_BASE_URL" => "http://openai.test/v1",
      "OPENAI_API_KEY" => nil,
      "OPENAI_VISION_MODEL" => "vision-test"
    ) do
      result = ImageDescriptionProviders::OpenaiProvider.new.generate(@image_core)

      assert_not result.success?
      assert_match "OPENAI_API_KEY", result.message
      assert_equal "failed", @image_core.reload.status
    end
  end

  test "openai provider handles api errors and rate limits" do
    with_openai_env do
      stub_request(:post, "http://openai.test/v1/chat/completions")
        .to_return(status: 429, body: { error: { message: "rate limited" } }.to_json)

      result = ImageDescriptionProviders::OpenaiProvider.new.generate(@image_core)

      assert_not result.success?
      assert_match "429", result.message
      assert_equal "failed", @image_core.reload.status
    end
  end

  test "openai provider handles timeouts" do
    with_openai_env do
      stub_request(:post, "http://openai.test/v1/chat/completions").to_timeout

      result = ImageDescriptionProviders::OpenaiProvider.new.generate(@image_core)

      assert_not result.success?
      assert_match "timed out", result.message
      assert_equal "failed", @image_core.reload.status
    end
  end

  test "openai provider handles unsupported responses" do
    with_openai_env do
      stub_request(:post, "http://openai.test/v1/chat/completions")
        .to_return(status: 200, body: { choices: [ { message: { content: "" } } ] }.to_json)

      result = ImageDescriptionProviders::OpenaiProvider.new.generate(@image_core)

      assert_not result.success?
      assert_match "unsupported response", result.message
      assert_equal "failed", @image_core.reload.status
    end
  end

  private

    def with_openai_env(&block)
      with_env({
        "IMAGE_DESCRIPTION_PROVIDER" => "openai",
        "OPENAI_API_BASE_URL" => "http://openai.test/v1",
        "OPENAI_API_KEY" => "test-key",
        "OPENAI_VISION_MODEL" => "vision-test"
      }, &block)
    end

    def with_env(values)
      old_values = values.keys.to_h { |key| [ key, ENV[key] ] }
      values.each do |key, value|
        value.nil? ? ENV.delete(key) : ENV[key] = value
      end
      yield
    ensure
      old_values.each do |key, value|
        value.nil? ? ENV.delete(key) : ENV[key] = value
      end
    end

    def openai_request_valid?(request)
      body = JSON.parse(request.body)
      image_url = body.dig("messages", 0, "content", 1, "image_url", "url")

      request.headers["Authorization"] == "Bearer test-key" &&
        body["model"] == "vision-test" &&
        image_url.start_with?("data:image/jpeg;base64,")
    end
end
