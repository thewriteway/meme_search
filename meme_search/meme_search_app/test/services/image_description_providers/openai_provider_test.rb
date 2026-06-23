# frozen_string_literal: true

require "test_helper"
require "fileutils"

class ImageDescriptionProviders::OpenaiProviderTest < ActiveSupport::TestCase
  def setup
    @image_dir = Rails.root.join("public", "memes", "openai_attempt_path")
    FileUtils.mkdir_p(@image_dir)
    @image_path = ImagePath.create!(name: "openai_attempt_path")
    @image_core = ImageCore.create!(name: "attempt.jpg", image_path: @image_path)
    File.binwrite(@image_dir.join(@image_core.name), "fake image bytes")
  end

  def teardown
    FileUtils.rm_rf(@image_dir) if @image_dir
    WebMock.reset!
  end

  test "does not save when attempt was canceled before provider runs" do
    attempt = @image_core.start_description_generation_attempt!(provider: "openai")
    @image_core.update!(status: :in_queue)
    attempt.cancel!

    with_openai_env do
      result = ImageDescriptionProviders::OpenaiProvider.new.generate(@image_core, attempt: attempt)

      assert_not result.success?
      assert_not_requested :post, "http://openai.test/v1/chat/completions"
    end

    assert_nil @image_core.reload.description
    assert_equal "canceled", attempt.reload.status
  end

  test "saves only through active attempt" do
    description = "A fresh active attempt description."
    attempt = @image_core.start_description_generation_attempt!(provider: "openai")
    @image_core.update!(status: :in_queue)

    with_openai_env do
      stub_request(:post, "http://openai.test/v1/chat/completions")
        .to_return(
          status: 200,
          body: { choices: [ { message: { content: description } } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      @image_core.stub(:refresh_description_embeddings, true) do
        ActionCable.server.stub(:broadcast, true) do
          result = ImageDescriptionProviders::OpenaiProvider.new.generate(@image_core, attempt: attempt)

          assert result.success?
        end
      end
    end

    assert_equal description, @image_core.reload.description
    assert_equal "done", @image_core.status
    assert_equal "succeeded", attempt.reload.status
  end

  private

    def with_openai_env
      old_values = {
        "IMAGE_DESCRIPTION_PROVIDER" => ENV["IMAGE_DESCRIPTION_PROVIDER"],
        "OPENAI_API_BASE_URL" => ENV["OPENAI_API_BASE_URL"],
        "OPENAI_API_KEY" => ENV["OPENAI_API_KEY"],
        "OPENAI_VISION_MODEL" => ENV["OPENAI_VISION_MODEL"]
      }
      ENV["IMAGE_DESCRIPTION_PROVIDER"] = "openai"
      ENV["OPENAI_API_BASE_URL"] = "http://openai.test/v1"
      ENV["OPENAI_API_KEY"] = "test-key"
      ENV["OPENAI_VISION_MODEL"] = "vision-test"
      yield
    ensure
      old_values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
end
