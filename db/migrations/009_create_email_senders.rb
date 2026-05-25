Sequel.migration do
  change do
    create_table(:email_senders) do
      primary_key :id
      String   :sender_name,  null: false
      String   :sender_email, null: false
      foreign_key :bank_id, :banks, on_delete: :cascade
      TrueClass :active, default: true
      DateTime :created_at
      DateTime :updated_at
    end
  end
end
