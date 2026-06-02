Sequel.migration do
  change do
    alter_table(:downloads) do
      add_column :log,       String, text: true
      add_column :backtrace, String, text: true
    end
  end
end
