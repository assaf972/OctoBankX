# Steps for the JSON API, exercised through Rack::Test (last_response).

def json_response
  JSON.parse(last_response.body)
end

# Dig into a parsed JSON body with a dotted path, e.g. "today.date".
def dig_json(path)
  path.split('.').reduce(json_response) do |acc, key|
    acc.is_a?(Array) ? acc[key.to_i] : acc[key]
  end
end

def send_json(method, path, body)
  send(method.downcase, path, body, 'CONTENT_TYPE' => 'application/json')
end

# --- Requests -------------------------------------------------------

When('I request {string}') do |path|
  get(path)
end

When('I request the latest download by id') do
  dl = Download.order(Sequel.desc(:id)).first
  get("/api/v1/downloads/#{dl.id}")
end

When('I enqueue a download via the API for bank {string} on {string}') do |name, date|
  bank = Bank.find(name: name)
  send_json('post', '/api/v1/downloads', { bank_id: bank.id, date: date }.to_json)
end

When('I enqueue a download via the API for bank {string} today') do |name|
  bank = Bank.find(name: name)
  send_json('post', '/api/v1/downloads', { bank_id: bank.id, date: Date.today.to_s }.to_json)
end

When('I enqueue a download via the API for bank {string} with no date') do |name|
  bank = Bank.find(name: name)
  send_json('post', '/api/v1/downloads', { bank_id: bank.id }.to_json)
end

When('I enqueue a download via the API with an empty body') do
  send_json('post', '/api/v1/downloads', '{}')
end

When('I enqueue a download via the API for a non-existent bank') do
  send_json('post', '/api/v1/downloads', { bank_id: 999_999 }.to_json)
end

When('I patch the latest download status to {string}') do |status|
  dl = Download.order(Sequel.desc(:id)).first
  send_json('patch', "/api/v1/downloads/#{dl.id}/status", { status: status }.to_json)
end

When('I patch the latest download with JSON:') do |doc|
  dl = Download.order(Sequel.desc(:id)).first
  send_json('patch', "/api/v1/downloads/#{dl.id}/status", doc)
end

When('I patch the status of download {int} to {string}') do |id, status|
  send_json('patch', "/api/v1/downloads/#{id}/status", { status: status }.to_json)
end

# --- Assertions -----------------------------------------------------

Then('the response status should be {int}') do |code|
  expect(last_response.status).to eq(code)
end

Then('the response content type should include {string}') do |type|
  expect(last_response.content_type).to include(type)
end

Then('the JSON response should include {string}') do |fragment|
  expect(last_response.body).to include(fragment)
end

Then('the JSON response should be an empty array') do
  expect(json_response).to eq []
end

Then('the JSON array should have {int} items') do |n|
  expect(json_response.size).to eq n
end

Then('every JSON item should have {string} equal to {string}') do |key, value|
  values = json_response.map { |item| item[key] }
  expect(values).not_to be_empty
  expect(values.uniq).to eq [value]
end

Then('each JSON item should include the keys {string}') do |csv|
  keys = csv.split(',').map(&:strip)
  expect(json_response.first.keys).to include(*keys)
end

Then('the JSON field {string} should equal {string}') do |path, value|
  expect(dig_json(path).to_s).to eq value
end

Then('the JSON field {string} should equal the number {int}') do |path, n|
  expect(dig_json(path)).to eq n
end

Then('the JSON field {string} should equal the current date') do |path|
  expect(dig_json(path)).to eq Date.today.to_s
end

Then('the JSON field {string} should be null') do |path|
  expect(dig_json(path)).to be_nil
end

Then('the JSON field {string} should not be null') do |path|
  expect(dig_json(path)).not_to be_nil
end

Then('the JSON totals should cover all four statuses') do
  expect(json_response['totals'].keys).to match_array(%w[pending running success failed])
end
