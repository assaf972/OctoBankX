Sequel.migration do
  change do
    alter_table(:banks) do
      add_column :ruler, :text
    end
  end
end
