require "application_system_test_case"

class ImageToTextsTest < ApplicationSystemTestCase
  test "visiting the index" do
    visit settings_image_to_texts_url
    assert_selector "h1", text: "Available models"
  end

  # collect all available model names by id
  model_names = ImageToText.all.map { |model| model.name }
  model_ids = ImageToText.all.map { |model| model.id }

  # log all model names
  puts "Model names: #{model_names}"

  # iterate through all available models and select / save each
  model_names.each_with_index do |model_name, index|
    test "updating the current model to #{model_name}" do
      visit image_to_texts_url
      # click on <input> with id = index
      find("input[id='#{model_ids[index]}']").click

      # click on "Save"
      click_on "Save"
      assert_text "Current model set to: #{model_name}"
    end
  end

end
