# frozen_string_literal: true

require "test_helper"

class Settings::ImageToTextsControllerTest < ActionDispatch::IntegrationTest
  test "index renders provider tabs and local models" do
    get settings_image_to_texts_path

    assert_response :success
    assert_select "h1", "AI Models"
    assert_select "button", text: "Local generator"
    assert_select "button", text: "OpenAI-compatible API"
    assert_select "#image_to_texts"
  end

  test "update_current saves local provider and selected local model" do
    model = image_to_texts(:one)
    DescriptionProviderSetting.current.update!(provider: "openai")

    post update_current_settings_image_to_texts_path, params: { current_id: model.id }

    assert_redirected_to settings_image_to_texts_path(provider_tab: "local")
    assert_equal "local", DescriptionProviderSetting.current.reload.provider
    assert model.reload.current?
  end

  test "update_current switches current model atomically" do
    previous_model = image_to_texts(:one)
    selected_model = image_to_texts(:two)
    previous_model.update!(current: true)
    selected_model.update!(current: false)
    DescriptionProviderSetting.current.update!(provider: "openai")

    post update_current_settings_image_to_texts_path, params: { current_id: selected_model.id }

    assert_redirected_to settings_image_to_texts_path(provider_tab: "local")
    assert_equal "local", DescriptionProviderSetting.current.reload.provider
    assert_not previous_model.reload.current?
    assert selected_model.reload.current?
  end

  test "update_current keeps selected model current when it was already current" do
    current_model = image_to_texts(:one)
    current_model.update!(current: true)
    DescriptionProviderSetting.current.update!(provider: "openai")

    post update_current_settings_image_to_texts_path, params: { current_id: current_model.id }

    assert_redirected_to settings_image_to_texts_path(provider_tab: "local")
    assert_equal "local", DescriptionProviderSetting.current.reload.provider
    assert current_model.reload.current?
    assert_equal 1, ImageToText.where(current: true).count
  end

  test "update_current preserves previous current model when selected model is missing" do
    current_model = image_to_texts(:one)
    current_model.update!(current: true)
    DescriptionProviderSetting.current.update!(provider: "openai")

    post update_current_settings_image_to_texts_path, params: { current_id: -1 }

    assert_redirected_to settings_image_to_texts_path(provider_tab: "local")
    assert_equal "local", DescriptionProviderSetting.current.reload.provider
    assert current_model.reload.current?
  end

  test "save_openai_settings saves cloud provider settings and redacts key" do
    post save_openai_settings_settings_image_to_texts_path, params: {
      description_provider_setting: {
        openai_base_url: "https://api.openai.com/v1",
        openai_model: "gpt-4.1-mini",
        openai_api_key: "sk-controller-1234abcd"
      }
    }

    assert_redirected_to settings_image_to_texts_path(provider_tab: "openai")
    setting = DescriptionProviderSetting.current.reload
    assert_equal "openai", setting.provider
    assert_equal "gpt-4.1-mini", setting.openai_model
    assert_equal "sk-controller-1234abcd", setting.openai_api_key
    assert_equal "sk-...abcd", setting.redacted_openai_api_key
  end

  test "save_openai_settings redirects with validation errors" do
    post save_openai_settings_settings_image_to_texts_path, params: {
      description_provider_setting: {
        openai_base_url: "https://api.openai.com/v1",
        openai_model: "made-up-model",
        openai_api_key: ""
      }
    }

    assert_redirected_to settings_image_to_texts_path(provider_tab: "openai")
    assert_match "Openai model is not included in the list", flash[:alert]
  end

  test "clear_openai_key removes saved key" do
    setting = DescriptionProviderSetting.current
    setting.openai_api_key = "sk-controller-1234abcd"
    setting.openai_last_test_status = "failed"
    setting.openai_last_tested_at = Time.current
    setting.openai_last_test_error = "401 Unauthorized"
    setting.save!

    delete clear_openai_key_settings_image_to_texts_path

    assert_redirected_to settings_image_to_texts_path(provider_tab: "openai")
    setting.reload
    assert_nil setting.openai_api_key
    assert_equal "Not saved", setting.redacted_openai_api_key
    assert_equal "not_tested", setting.openai_last_test_status
    assert_nil setting.openai_last_tested_at
    assert_nil setting.openai_last_test_error
  end

  test "test_openai_settings redirects to OpenAI provider tab" do
    post test_openai_settings_settings_image_to_texts_path

    assert_redirected_to settings_image_to_texts_path(provider_tab: "openai")
  end
end
