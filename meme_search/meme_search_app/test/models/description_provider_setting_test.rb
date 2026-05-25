# frozen_string_literal: true

require "test_helper"

class DescriptionProviderSettingTest < ActiveSupport::TestCase
  test "current returns a singleton local setting by default" do
    setting = DescriptionProviderSetting.current

    assert setting.persisted?
    assert_equal DescriptionProviderSetting::SINGLETON_KEY, setting.singleton_key
    assert_equal "local", setting.provider
    assert_equal "https://api.openai.com/v1", setting.openai_base_url
    assert_equal "gpt-4o-mini", setting.openai_model
  end

  test "database enforces a single settings row" do
    DescriptionProviderSetting.current
    duplicate = DescriptionProviderSetting.new(singleton_key: DescriptionProviderSetting::SINGLETON_KEY)

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "singleton key only allows the canonical value" do
    setting = DescriptionProviderSetting.new(singleton_key: 1)

    assert_not setting.valid?
    assert_includes setting.errors[:singleton_key], "is not included in the list"
  end

  test "database rejects non canonical singleton key when validations are skipped" do
    setting = DescriptionProviderSetting.new(singleton_key: 1)

    assert_raises(ActiveRecord::StatementInvalid) { setting.save!(validate: false) }
  end

  test "provider only allows local and openai" do
    setting = DescriptionProviderSetting.current
    setting.provider = "unsupported"

    assert_not setting.valid?
    assert_includes setting.errors[:provider], "is not included in the list"
  end

  test "openai model only allows fixed model list" do
    setting = DescriptionProviderSetting.current
    setting.openai_model = "made-up-model"

    assert_not setting.valid?
    assert_includes setting.errors[:openai_model], "is not included in the list"
  end

  test "api key is encrypted, redacted, and recoverable" do
    setting = DescriptionProviderSetting.current
    setting.openai_api_key = "sk-test-1234567890abcd"
    setting.save!

    setting.reload
    assert_not_equal "sk-test-1234567890abcd", setting.openai_api_key_ciphertext
    assert_equal "sk-test-1234567890abcd", setting.openai_api_key
    assert_equal "abcd", setting.openai_key_last_four
    assert_equal "sk-...abcd", setting.redacted_openai_api_key
  end

  test "clear_openai_api_key removes encrypted key and metadata" do
    setting = DescriptionProviderSetting.current
    setting.openai_api_key = "sk-test-1234567890abcd"
    setting.save!

    setting.clear_openai_api_key
    setting.save!

    setting.reload
    assert_nil setting.openai_api_key
    assert_nil setting.openai_api_key_ciphertext
    assert_nil setting.openai_key_last_four
    assert_equal "Not saved", setting.redacted_openai_api_key
  end
end
