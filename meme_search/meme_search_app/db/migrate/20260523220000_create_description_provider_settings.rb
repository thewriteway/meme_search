# frozen_string_literal: true

class CreateDescriptionProviderSettings < ActiveRecord::Migration[8.0]
  def up
    create_table :description_provider_settings do |t|
      t.integer :singleton_key, null: false, default: 0
      t.string :provider, null: false, default: "local"
      t.string :openai_base_url, null: false, default: "https://api.openai.com/v1"
      t.string :openai_model, null: false, default: "gpt-4o-mini"
      t.text :openai_api_key_ciphertext
      t.string :openai_key_last_four
      t.string :openai_last_test_status, null: false, default: "not_tested"
      t.datetime :openai_last_tested_at
      t.text :openai_last_test_error

      t.timestamps
    end

    add_index :description_provider_settings, :singleton_key, unique: true
    add_check_constraint :description_provider_settings,
      "singleton_key = 0",
      name: "description_provider_settings_singleton_key_check"
  end

  def down
    drop_table :description_provider_settings
  end
end
