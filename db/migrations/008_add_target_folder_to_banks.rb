Sequel.migration do
  change do
    alter_table(:banks) do
      add_column :target_folder, String
    end
  end
end
