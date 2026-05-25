# frozen_string_literal: true

class CreateImageDescriptionBulkOperations < ActiveRecord::Migration[8.0]
  def change
    create_table :image_description_bulk_operations do |t|
      t.string :provider, null: false
      t.boolean :provider_queued, null: false, default: true
      t.integer :status, null: false, default: 0
      t.integer :total_count, null: false, default: 0
      t.jsonb :filter_params, null: false, default: {}
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.datetime :canceled_at

      t.timestamps
    end

    add_reference :image_description_generation_attempts,
      :image_description_bulk_operation,
      foreign_key: { on_delete: :nullify },
      index: { name: "index_generation_attempts_on_bulk_operation_id" }
  end
end
