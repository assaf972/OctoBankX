Sequel.migration do
  change do
    create_table(:banks) do
      primary_key :id
      String :name, null: false
      String :sftp_host, null: false
      Integer :sftp_port, default: 22
      String :sftp_remote_path, default: '/'
      DateTime :created_at
      DateTime :updated_at
    end
  end
end
