Sequel.migration do
  change do
    alter_table(:banks) do
      add_column :parser, String
    end
  end
end
