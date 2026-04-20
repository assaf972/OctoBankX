Sequel.migration do
  change do
    create_table(:accounts) do
      primary_key :id
      String :name, null: false
      String :account_no, null: false
      foreign_key :bank_id, :banks, null: false
      String :branch
      String :currency, default: 'USD'
      Float :balance, default: 0.0
      Date :balance_date
      String :sftp_username
      String :sftp_password
      DateTime :created_at
      DateTime :updated_at
    end
  end
end
