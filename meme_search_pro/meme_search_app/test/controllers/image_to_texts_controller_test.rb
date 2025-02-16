require "test_helper"

class ImageToTextsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @image_to_text = image_to_texts(:one)
  end

  test "should get index" do
    get image_to_texts_url
    assert_response :success
  end

  test "should get new" do
    get new_image_to_text_url
    assert_response :success
  end

  test "should create image_to_text" do
    assert_difference("ImageToText.count") do
      post image_to_texts_url, params: { image_to_text: { description: @image_to_text.description, name: @image_to_text.name } }
    end

    assert_redirected_to image_to_text_url(ImageToText.last)
  end

  test "should show image_to_text" do
    get image_to_text_url(@image_to_text)
    assert_response :success
  end

  test "should get edit" do
    get edit_image_to_text_url(@image_to_text)
    assert_response :success
  end

  test "should update image_to_text" do
    patch image_to_text_url(@image_to_text), params: { image_to_text: { description: @image_to_text.description, name: @image_to_text.name } }
    assert_redirected_to image_to_text_url(@image_to_text)
  end

  test "should destroy image_to_text" do
    assert_difference("ImageToText.count", -1) do
      delete image_to_text_url(@image_to_text)
    end

    assert_redirected_to image_to_texts_url
  end
end
