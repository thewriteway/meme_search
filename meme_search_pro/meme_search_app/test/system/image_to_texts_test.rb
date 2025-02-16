require "application_system_test_case"

class ImageToTextsTest < ApplicationSystemTestCase
  setup do
    @image_to_texts = image_to_texts(:one, :two)
  end


  test "visiting the index" do
    visit settings_image_to_texts_url
    assert_selector "h1", text: "Available models"
  end

  test "updating the current model to all available models" do
    # collect all available model names by id
    model_names = @image_to_texts.map { |model| model.name }
    model_ids = @image_to_texts.map { |model| model.id }

    # iterate through names by index
    model_names.each_with_index do |model_name, index|
      visit settings_image_to_texts_url

      # assert not selected
      assert find("input[id='#{model_ids[index]}']", visible: :all).checked? == false

      # toggle on <input> with id = index visible all
      find("label[for='#{model_ids[index]}']", visible: :all).click

      # assert that toggle is now on
      assert find("input[id='#{model_ids[index]}']", visible: :all).checked?

      # assert all other toggles are off
      model_ids.each_with_index do |id, i|
        if i != index
          assert find("input[id='#{id}']", visible: :all).checked? == false
        end
      end
    end
  end
end
