Sequel.migration do
  change do
    create_table(:api_calls) do
      primary_key :id
      String   :http_method,   null: false          # GET, POST, PATCH …
      String   :endpoint,      null: false          # /api/v1/accounts
      String   :host                                # caller IP / hostname
      Integer  :account_id                          # nullable — no FK, account may not exist
      String   :status,        null: false          # success | failed
      Integer  :http_status                         # 200, 201, 404, 422 …
      Integer  :duration_ms                         # round-trip ms
      String   :error_message                       # parsed from response body on failure
      DateTime :created_at,    null: false

      index :status
      index :endpoint
      index :account_id
      index :created_at
    end
  end
end
