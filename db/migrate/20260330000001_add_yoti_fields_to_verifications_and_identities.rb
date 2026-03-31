class AddYotiFieldsToVerificationsAndIdentities < ActiveRecord::Migration[8.0]
  def change
    change_table :verifications do |t|
      t.string :yoti_session_id
      t.string :yoti_status
      t.datetime :yoti_completed_at
      t.integer :yoti_verified_age
      t.boolean :auto_approved, default: false, null: false

      t.index :yoti_session_id, unique: true
    end
  end
end
