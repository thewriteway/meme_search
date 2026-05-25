# frozen_string_literal: true

module Settings
  class ImageToTextsController < ApplicationController
    def index
      @image_to_texts = ImageToText.order(id: :asc)
      @provider_setting = DescriptionProviderSetting.current
      @provider_configuration = ImageDescriptionProviders::Configuration.current
      @provider_tab = params[:provider_tab].presence || @provider_setting.provider
    end

    def update_current
      selected_model = ImageToText.find(params[:current_id]) if params[:current_id].present?

      if selected_model.present?
        ImageToText.transaction do
          ImageToText.lock.where(current: true).load
          DescriptionProviderSetting.current.update!(provider: "local")
          ImageToText.update_all(current: false)
          ImageToText.where(id: selected_model.id).update_all(current: true, updated_at: Time.current)
        end
      else
        DescriptionProviderSetting.current.update!(provider: "local")
      end

      current_model = ImageToText.find_by(current: true)&.name

      redirect_to settings_image_to_texts_path(provider_tab: "local"), notice: "Current model set to: #{current_model}"
    rescue ActiveRecord::RecordNotFound
      DescriptionProviderSetting.current.update!(provider: "local")
      redirect_to settings_image_to_texts_path(provider_tab: "local"), alert: "Selected local model was not found."
    end

    def save_openai_settings
      setting = DescriptionProviderSetting.current
      attrs = description_provider_setting_params
      setting.provider = "openai"
      setting.openai_base_url = attrs[:openai_base_url]
      setting.openai_model = attrs[:openai_model]
      setting.openai_api_key = attrs[:openai_api_key] if attrs[:openai_api_key].present?
      setting.openai_last_test_status = "not_tested"
      setting.openai_last_tested_at = nil
      setting.openai_last_test_error = nil
      setting.save!

      redirect_to settings_image_to_texts_path(provider_tab: "openai"), notice: "OpenAI-compatible provider settings saved."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to settings_image_to_texts_path(provider_tab: "openai"), alert: e.record.errors.full_messages.to_sentence
    end

    def clear_openai_key
      setting = DescriptionProviderSetting.current
      setting.clear_openai_api_key
      setting.openai_last_test_status = "not_tested"
      setting.openai_last_tested_at = nil
      setting.openai_last_test_error = nil
      setting.save!

      redirect_to settings_image_to_texts_path(provider_tab: "openai"), notice: "Saved OpenAI API key cleared."
    end

    def test_openai_settings
      setting = DescriptionProviderSetting.current
      result = ImageDescriptionProviders::OpenaiProvider.new.test_connection

      setting.openai_last_test_status = result.success? ? "passed" : "failed"
      setting.openai_last_tested_at = Time.current
      setting.openai_last_test_error = result.success? ? nil : result.message
      setting.save!

      if result.success?
        redirect_to settings_image_to_texts_path(provider_tab: "openai"), notice: result.message
      else
        redirect_to settings_image_to_texts_path(provider_tab: "openai"), alert: result.message
      end
    end

    private

      def description_provider_setting_params
        params.require(:description_provider_setting).permit(:openai_base_url, :openai_model, :openai_api_key)
      end
  end
end
