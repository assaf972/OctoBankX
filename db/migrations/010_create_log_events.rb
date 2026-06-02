Sequel.migration do
  change do
    create_table(:log_events) do
      primary_key :id
      foreign_key :download_id, :downloads, null: true, on_delete: :cascade
      String   :kind,        null: false        # log / error / exception / notification
      String   :message,     text: true
      String   :error_class
      String   :backtrace,   text: true
      DateTime :created_at

      index :download_id
      index :kind
    end
  end
end
