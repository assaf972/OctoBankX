Sequel.migration do
  change do
    create_table(:downloads) do
      primary_key :id
      foreign_key :account_id, :accounts, null: false
      foreign_key :bank_id, :banks, null: false
      Date :date, null: false
      String :status, default: 'pending'  # pending, running, success, failed
      String :error_message
      String :file_path
      DateTime :started_at
      DateTime :completed_at
      DateTime :created_at
    end
  end
end
