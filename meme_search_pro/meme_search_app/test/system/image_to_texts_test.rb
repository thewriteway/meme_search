require "application_system_test_case"

class ImageToTextsTest < ApplicationSystemTestCase
  setup do
    @image_to_text = image_to_texts(:one)
  end

  test "visiting the index" do
    visit image_to_texts_url
    assert_selector "h1", text: "Image to texts"
  end

  test "should create image to text" do
    visit image_to_texts_url
    click_on "New image to text"

    fill_in "Description", with: @image_to_text.description
    fill_in "Name", with: @image_to_text.name
    click_on "Create Image to text"

    assert_text "Image to text was successfully created"
    click_on "Back"
  end

  test "should update Image to text" do
    visit image_to_text_url(@image_to_text)
    click_on "Edit this image to text", match: :first

    fill_in "Description", with: @image_to_text.description
    fill_in "Name", with: @image_to_text.name
    click_on "Update Image to text"

    assert_text "Image to text was successfully updated"
    click_on "Back"
  end

  test "should destroy Image to text" do
    visit image_to_text_url(@image_to_text)
    click_on "Destroy this image to text", match: :first

    assert_text "Image to text was successfully destroyed"
  end
end
