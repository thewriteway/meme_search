# frozen_string_literal: true

class CreateImageDescriptionGenerationAttempts < ActiveRecord::Migration[8.0]
  def change
    create_table :image_description_generation_attempts do |t|
      t.references :image_core, null: false, foreign_key: { on_delete: :cascade }
      t.string :provider, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :provider_settings, null: false, default: {}
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :canceled_at

      t.timestamps
    end

    add_index :image_description_generation_attempts,
      :image_core_id,
      unique: true,
      where: "status IN (0, 1)",
      name: "index_generation_attempts_one_active_per_image"
  end
end
