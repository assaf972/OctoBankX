require 'sinatra/base'
require 'sinatra/reloader'
require 'i18n'

require_relative 'db/database'
require_relative 'models/bank'
require_relative 'models/account'
require_relative 'models/download'
require_relative 'models/setting'
require_relative 'models/api_call'
require_relative 'jobs/download_job'

class OctoBankXApp < Sinatra::Base
  configure :development do
    register Sinatra::Reloader
    also_reload 'models/**/*.rb'
    also_reload 'jobs/**/*.rb'
    also_reload 'helpers/**/*.rb'
  end

  configure do
    set :root,          File.dirname(__FILE__)
    set :views,         File.join(File.dirname(__FILE__), 'views')
    set :public_folder, File.join(File.dirname(__FILE__), 'public')
    enable :sessions
    set :session_secret, ENV.fetch('SESSION_SECRET', SecureRandom.hex(32))

    I18n.load_path      += Dir[File.join(File.dirname(__FILE__), 'config', 'locales', '*.yml')]
    I18n.available_locales = %i[en he]
    I18n.default_locale    = :en
    I18n.backend.load_translations
  end

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------
  helpers do
    def t(key, **opts)
      I18n.t(key, **opts)
    end

    def locale_dir
      I18n.locale == :he ? 'rtl' : 'ltr'
    end

    def flash(type, message)
      session[:flash] = { type: type, message: message }
    end

    def consume_flash
      session.delete(:flash)
    end
  end

  before do
    @flash = consume_flash
    # Persist locale choice in session; honour ?lang= param on any request
    if params[:lang] && I18n.available_locales.map(&:to_s).include?(params[:lang])
      session[:locale] = params[:lang]
    end
    I18n.locale = (session[:locale] || :en).to_sym
  end

  # ------------------------------------------------------------------
  # Locale switcher
  # ------------------------------------------------------------------
  get '/locale' do
    lang = params[:lang].to_s
    session[:locale] = lang if I18n.available_locales.map(&:to_s).include?(lang)
    redirect(request.referer || '/')
  end

  # ------------------------------------------------------------------
  # Home
  # ------------------------------------------------------------------
  get '/' do
    @recent_downloads = Download.recent(10).eager(:account, :bank).all
    @accounts         = Account.eager(:bank).all
    @banks            = Bank.all
    erb :home
  end

  # ------------------------------------------------------------------
  # Accounts
  # ------------------------------------------------------------------
  post '/accounts' do
    account = Account.new(
      name:           params[:name],
      account_no:     params[:account_no],
      bank_id:        params[:bank_id].to_i,
      branch:         params[:branch],
      currency:       params[:currency] || 'USD',
      balance:        params[:balance].to_f,
      balance_date:   params[:balance_date].empty? ? nil : Date.parse(params[:balance_date]),
      sftp_username:  params[:sftp_username],
      sftp_password:  params[:sftp_password],
      created_at:     Time.now,
      updated_at:     Time.now
    )

    if account.valid? && account.save
      flash :success, t('flash.account_created', name: account.name)
    else
      flash :error, t('flash.account_error', errors: account.errors.full_messages.join(', '))
    end
    redirect '/'
  end

  # ------------------------------------------------------------------
  # Banks
  # ------------------------------------------------------------------
  get '/banks' do
    @banks = Bank.all
    erb :banks
  end

  post '/banks' do
    bank = Bank.new(
      name:             params[:name],
      sftp_host:        params[:sftp_host],
      sftp_port:        params[:sftp_port].to_i,
      sftp_remote_path: params[:sftp_remote_path] || '/',
      created_at:       Time.now,
      updated_at:       Time.now
    )

    if bank.valid? && bank.save
      flash :success, t('flash.bank_added', name: bank.name)
    else
      flash :error, t('flash.bank_error', errors: bank.errors.full_messages.join(', '))
    end
    redirect '/banks'
  end

  # ------------------------------------------------------------------
  # Jobs
  # ------------------------------------------------------------------
  get '/jobs' do
    scope = Download.eager(:account, :bank)
    scope = scope.where(status: params[:status]) unless params[:status].to_s.empty?
    scope = scope.where(date: Date.parse(params[:date])) unless params[:date].to_s.empty?
    @filter_date = params[:date] || Date.today.to_s
    @downloads   = scope.order(Sequel.desc(:created_at)).all
    erb :jobs
  end

  post '/jobs/run' do
    Thread.new { DownloadJob.run(date: Date.today) }
    flash :success, t('flash.job_triggered')
    redirect '/jobs'
  end

  # ------------------------------------------------------------------
  # Log
  # ------------------------------------------------------------------
  get '/log' do
    scope = Download.eager(:account, :bank)
    scope = scope.where(account_id: params[:account_id].to_i) unless params[:account_id].to_s.empty?
    scope = scope.where(status: params[:status])              unless params[:status].to_s.empty?
    scope = scope.where { date >= Date.parse(params[:from]) } unless params[:from].to_s.empty?
    scope = scope.where { date <= Date.parse(params[:to]) }   unless params[:to].to_s.empty?

    @filter_account_id = params[:account_id]
    @filter_status     = params[:status]
    @filter_from       = params[:from]
    @filter_to         = params[:to]
    @accounts          = Account.all
    @downloads         = scope.order(Sequel.desc(:created_at)).limit(500).all
    erb :log
  end

  # ------------------------------------------------------------------
  # Settings
  # ------------------------------------------------------------------
  get '/settings' do
    @settings = Setting.order(:key).all
    erb :settings
  end

  post '/settings' do
    (params[:settings] || {}).each do |key, value|
      Setting.set(key, value)
    end
    flash :success, t('flash.settings_saved')
    redirect '/settings'
  end

  # ------------------------------------------------------------------
  # API Calls log
  # ------------------------------------------------------------------
  get '/api-calls' do
    scope = ApiCall.order(Sequel.desc(:created_at))
    scope = scope.where(status:   params[:status])   unless params[:status].to_s.empty?
    scope = scope.where(http_method: params[:method]) unless params[:method].to_s.empty?
    scope = scope.where(endpoint: params[:endpoint]) unless params[:endpoint].to_s.empty?
    scope = scope.where { created_at >= Time.parse(params[:from]) } unless params[:from].to_s.empty?
    scope = scope.where { created_at <= Time.parse(params[:to]) + 86_399 } unless params[:to].to_s.empty?

    @filter_status   = params[:status]
    @filter_method   = params[:method]
    @filter_endpoint = params[:endpoint]
    @filter_from     = params[:from]
    @filter_to       = params[:to]
    @endpoints       = ApiCall.distinct_endpoints
    @api_calls       = scope.limit(500).all
    erb :api_calls
  end

  # ==================================================================
  # JSON API  — /api/v1
  # ==================================================================
  before '/api/*' do
    content_type :json
    @api_start_time  = Time.now
    @api_account_id  = nil
    if request.content_type&.include?('application/json')
      body = request.body.read
      @json_params = body.empty? ? {} : JSON.parse(body, symbolize_names: true)
    else
      @json_params = {}
    end
  end

  after '/api/*' do
    next unless @api_start_time

    begin
      duration_ms = ((Time.now - @api_start_time) * 1000).round
      http_st     = response.status.to_i
      call_status = http_st < 400 ? 'success' : 'failed'

      error_msg = nil
      if http_st >= 400
        begin
          raw = response.body.respond_to?(:join) ? response.body.join : response.body.to_s
          error_msg = JSON.parse(raw)['error']
        rescue
        end
      end

      ApiCall.create(
        http_method:   request.request_method,
        endpoint:      request.path_info,
        host:          request.ip,
        account_id:    @api_account_id,
        status:        call_status,
        http_status:   http_st,
        duration_ms:   duration_ms,
        error_message: error_msg,
        created_at:    Time.now
      )
    rescue => e
      warn "ApiCall logging error: #{e.message}"
    end
  end

  helpers do
    def json_body
      @json_params || {}
    end

    def api_error(status_code, message)
      halt status_code, { error: message }.to_json
    end

    def paginate(dataset, default_limit: 50)
      raw   = params[:limit].to_s
      limit = raw.empty? ? default_limit : [[raw.to_i, 1].max, 200].min
      offset = [params[:offset].to_i, 0].max
      dataset.limit(limit).offset(offset)
    end
  end

  # ------------------------------------------------------------------
  # GET /api/v1/accounts
  # ------------------------------------------------------------------
  get '/api/v1/accounts' do
    accounts = Account.eager(:bank).order(:name).all
    accounts.map { |a|
      {
        id:           a.id,
        name:         a.name,
        account_no:   a.account_no,
        bank_id:      a.bank_id,
        bank_name:    a.bank&.name,
        branch:       a.branch,
        currency:     a.currency,
        balance:      a.balance,
        balance_date: a.balance_date&.to_s
      }
    }.to_json
  end

  # ------------------------------------------------------------------
  # GET /api/v1/accounts/:id
  # ------------------------------------------------------------------
  get '/api/v1/accounts/:id' do
    @api_account_id = params[:id].to_i
    a = Account.eager(:bank).first(id: @api_account_id)
    api_error(404, 'Account not found') unless a
    {
      id:           a.id,
      name:         a.name,
      account_no:   a.account_no,
      bank_id:      a.bank_id,
      bank_name:    a.bank&.name,
      branch:       a.branch,
      currency:     a.currency,
      balance:      a.balance,
      balance_date: a.balance_date&.to_s,
      created_at:   a.created_at&.iso8601,
      updated_at:   a.updated_at&.iso8601
    }.to_json
  end

  # ------------------------------------------------------------------
  # GET /api/v1/downloads
  # ------------------------------------------------------------------
  get '/api/v1/downloads' do
    @api_account_id = params[:account_id].to_i unless params[:account_id].to_s.empty?
    scope = Download.eager(:account, :bank).order(Sequel.desc(:created_at))
    scope = scope.where(status:     params[:status])            unless params[:status].to_s.empty?
    scope = scope.where(account_id: params[:account_id].to_i)  unless params[:account_id].to_s.empty?
    scope = scope.where(date:       Date.parse(params[:date]))  unless params[:date].to_s.empty?

    paginate(scope).all.map { |dl| serialize_download(dl) }.to_json
  end

  # ------------------------------------------------------------------
  # GET /api/v1/downloads/:id
  # ------------------------------------------------------------------
  get '/api/v1/downloads/:id' do
    dl = Download.eager(:account, :bank).first(id: params[:id].to_i)
    api_error(404, 'Download not found') unless dl
    @api_account_id = dl.account_id
    serialize_download(dl).to_json
  end

  # ------------------------------------------------------------------
  # POST /api/v1/downloads  — enqueue a download for an account
  # ------------------------------------------------------------------
  post '/api/v1/downloads' do
    p = json_body
    account_id = (p[:account_id] || params[:account_id]).to_i
    date_str   = p[:date] || params[:date]
    date       = date_str ? Date.parse(date_str.to_s) : Date.today

    @api_account_id = account_id unless account_id.zero?
    api_error(422, 'account_id is required') if account_id.zero?

    account = Account.first(id: account_id)
    api_error(404, 'Account not found') unless account

    if Download.where(account_id: account.id, date: date).count > 0
      api_error(409, "Download already exists for account #{account_id} on #{date}")
    end

    dl = Download.create(
      account_id: account.id,
      bank_id:    account.bank_id,
      date:       date,
      status:     'pending',
      created_at: Time.now
    )

    status 201
    serialize_download(dl).to_json
  end

  # ------------------------------------------------------------------
  # PATCH /api/v1/downloads/:id/status
  # ------------------------------------------------------------------
  patch '/api/v1/downloads/:id/status' do
    dl = Download.first(id: params[:id].to_i)
    api_error(404, 'Download not found') unless dl
    @api_account_id = dl.account_id

    p          = json_body
    new_status = (p[:status] || params[:status]).to_s

    api_error(422, "Invalid status '#{new_status}'") unless Download::STATUSES.include?(new_status)

    case new_status
    when 'running'  then dl.mark_running!
    when 'success'  then dl.mark_success!(p[:file_path] || params[:file_path])
    when 'failed'   then dl.mark_failed!(p[:error_message] || params[:error_message] || 'Unknown error')
    else            dl.update(status: new_status)
    end

    serialize_download(dl.reload).to_json
  end

  # ------------------------------------------------------------------
  # GET /api/v1/status  — system health snapshot
  # ------------------------------------------------------------------
  get '/api/v1/status' do
    today = Date.today

    counts = Download::STATUSES.each_with_object({}) do |s, h|
      h[s] = Download.where(status: s).count
    end

    today_counts = Download::STATUSES.each_with_object({}) do |s, h|
      h[s] = Download.where(status: s, date: today).count
    end

    last_success = Download.where(status: 'success').order(Sequel.desc(:completed_at)).first
    last_failure = Download.where(status: 'failed').order(Sequel.desc(:completed_at)).first

    {
      status:          'ok',
      timestamp:       Time.now.iso8601,
      totals:          counts,
      today:           { date: today.to_s, **today_counts },
      accounts_count:  Account.count,
      banks_count:     Bank.count,
      last_success: last_success ? {
        id:           last_success.id,
        account_id:   last_success.account_id,
        date:         last_success.date.to_s,
        completed_at: last_success.completed_at&.iso8601
      } : nil,
      last_failure: last_failure ? {
        id:            last_failure.id,
        account_id:    last_failure.account_id,
        date:          last_failure.date.to_s,
        error_message: last_failure.error_message,
        completed_at:  last_failure.completed_at&.iso8601
      } : nil
    }.to_json
  end

  # ------------------------------------------------------------------
  # Private serializer (used across API routes)
  # ------------------------------------------------------------------
  private

  def serialize_download(dl)
    {
      id:            dl.id,
      account_id:    dl.account_id,
      account_name:  dl.account&.name,
      account_no:    dl.account&.account_no,
      bank_id:       dl.bank_id,
      bank_name:     dl.bank&.name,
      date:          dl.date.to_s,
      status:        dl.status,
      error_message: dl.error_message,
      file_path:     dl.file_path,
      started_at:    dl.started_at&.iso8601,
      completed_at:  dl.completed_at&.iso8601,
      duration_s:    dl.duration&.round(2),
      created_at:    dl.created_at&.iso8601
    }
  end
end
