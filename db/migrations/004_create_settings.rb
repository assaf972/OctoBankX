Sequel.migration do
  change do
    create_table(:settings) do
      primary_key :id
      String :key, null: false, unique: true
      String :value
      String :description
      DateTime :updated_at
    end

    # Seed default settings
    from(:settings).insert(
      key: 'download_dir',
      value: '/tmp/octobankx/downloads',
      description: 'Local directory where downloaded bank statements are stored',
      updated_at: Time.now
    )
    from(:settings).insert(
      key: 'sftp_timeout',
      value: '30',
      description: 'SFTP connection timeout in seconds',
      updated_at: Time.now
    )
    from(:settings).insert(
      key: 'job_schedule',
      value: '0 6 * * *',
      description: 'Cron expression for daily download job (default: 6am daily)',
      updated_at: Time.now
    )
    from(:settings).insert(
      key: 'retention_days',
      value: '90',
      description: 'Number of days to keep download history',
      updated_at: Time.now
    )
  end
end
