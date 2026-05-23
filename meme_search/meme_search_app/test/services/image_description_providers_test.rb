# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "minitest/mock"

class ImageDescriptionProvidersTest < ActiveSupport::TestCase
  def setup
    @image_dir = Rails.root.join("public", "memes", "provider_test_path")
    FileUtils.mkdir_p(@image_dir)
    @image_path = ImagePath.create!(name: "provider_test_path")
    @image_core = ImageCore.create!(name: "provider_test.jpg", image_path: @image_path)
    @image_file = @image_dir.join(@image_core.name)
    File.binwrite(@image_file, "fake image bytes")
  end

  def teardown
    FileUtils.rm_rf(@image_dir) if @image_dir
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

  test "local provider reports asynchronous queue behavior" do
    provider = ImageDescriptionProviders::LocalProvider.new

    assert provider.queued_provider?
    assert_equal "local", provider.name
  end

  test "local provider waits longer than generator status callback timeout" do
    assert_operator ImageDescriptionProviders::LocalProvider::READ_TIMEOUT, :>, 30
  end

  test "openai provider reports inline generation behavior" do
    provider = ImageDescriptionProviders::OpenaiProvider.new

    assert_not provider.queued_provider?
    assert_equal "openai", provider.name
  end

  test "result exposes predicate helpers without relying on Ruby Data" do
    result = ImageDescriptionProviders::Result.new(success: true, message: "Queued", queued: true)

    assert result.success
    assert result.success?
    assert result.queued
    assert result.queued?
    assert_equal "Queued", result.message
  end

  test "openai provider saves description and broadcasts on success" do
    description = "A meme with visible text and a joke."
    broadcasts = []

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
          broadcasts << [ channel, data ]
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
    description_broadcast = broadcasts.find { |entry| entry[0] == "image_description_channel" }
    done_status_broadcast = broadcasts.find { |entry|
      entry[0] == "image_status_channel" && entry[1][:status_html].include?("done")
    }
    assert_equal description, description_broadcast.last[:description]
    assert_equal "description-image-core-id-#{@image_core.id}", description_broadcast.last[:div_id]
    assert_equal "status-image-core-id-#{@image_core.id}", done_status_broadcast.last[:div_id]
  end

  test "openai provider fails gracefully when api key is missing" do
    with_env(
      "IMAGE_DESCRIPTION_PROVIDER" => "openai",
      "OPENAI_API_BASE_URL" => "http://openai.test/v1",
      "OPENAI_API_KEY" => nil,
      "OPENAI_VISION_MODEL" => "vision-test"
    ) do
      broadcasts = []

      ActionCable.server.stub(:broadcast, ->(channel, data) {
        broadcasts << [ channel, data ]
      }) do
        result = ImageDescriptionProviders::OpenaiProvider.new.generate(@image_core)

        assert_not result.success?
        assert_match "OPENAI_API_KEY", result.message
        assert_equal "failed", @image_core.reload.status
      end

      failed_status_broadcast = broadcasts.find { |entry|
        entry[0] == "image_status_channel" && entry[1][:status_html].include?("failed")
      }
      assert_equal "status-image-core-id-#{@image_core.id}", failed_status_broadcast.last[:div_id]
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

  test "openai provider truncates long descriptions to image validation limit" do
    long_description = "A" * 700

    with_openai_env do
      stub_request(:post, "http://openai.test/v1/chat/completions")
        .to_return(
          status: 200,
          body: { choices: [ { message: { content: long_description } } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      @image_core.stub(:refresh_description_embeddings, true) do
        ActionCable.server.stub(:broadcast, true) do
          result = ImageDescriptionProviders::OpenaiProvider.new.generate(@image_core)

          assert result.success?
        end
      end
    end

    @image_core.reload
    assert_equal 500, @image_core.description.length
    assert_equal "done", @image_core.status
  end

  test "openai provider fails when normalized description is blank" do
    with_openai_env do
      stub_request(:post, "http://openai.test/v1/chat/completions")
        .to_return(
          status: 200,
          body: { choices: [ { message: { content: "   \n\t   " } } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

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
        body["max_tokens"] == 160 &&
        image_url.start_with?("data:image/jpeg;base64,")
    end
end
