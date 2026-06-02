require 'sinatra/base'
require 'sinatra/reloader'
require 'i18n'

require_relative 'db/database'
require_relative 'models/bank'
require_relative 'models/download'
require_relative 'models/setting'
require_relative 'models/email_sender'
require_relative 'jobs/download_job'
require_relative 'jobs/email_listener_job'
require_relative 'parsers/base_parser'
require_relative 'parsers/leumi_parser'
require_relative 'parsers/poalim_parser'
require_relative 'parsers/discount_parser'
require_relative 'parsers/fibi_parser'

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
    @recent_downloads = Download.recent(10).eager(:bank).all
    @banks            = Bank.all

    # Dashboard stats
    today = Date.today
    @total_banks     = @banks.size
    @today_success   = Download.where(status: 'success', date: today).count
    @today_failed    = Download.where(status: 'failed',  date: today).count
    @today_pending   = Download.where(status: 'pending', date: today).count
    @today_running   = Download.where(status: 'running', date: today).count
    @total_downloads = Download.count

    # Last 7 days download counts for bar chart
    @chart_dates    = (6.downto(0)).map { |i| today - i }
    @chart_success  = @chart_dates.map { |d| Download.where(status: 'success', date: d).count }
    @chart_failed   = @chart_dates.map { |d| Download.where(status: 'failed',  date: d).count }

    # Status distribution for doughnut chart
    @status_counts = {
      success: Download.where(status: 'success').count,
      failed:  Download.where(status: 'failed').count,
      pending: Download.where(status: 'pending').count,
      running: Download.where(status: 'running').count
    }

    erb :home
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
      ruler:            params[:ruler],
      parser:           params[:parser],
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
    scope = Download.eager(:bank)
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
  # Job detail
  # ------------------------------------------------------------------
  get '/jobs/:id' do
    @download = Download.eager(:bank).first(id: params[:id].to_i)
    halt 404, 'Job not found' unless @download
    erb :job
  end

  post '/jobs/:id/rerun' do
    dl = Download.first(id: params[:id].to_i)
    if dl
      DownloadJob.rerun(dl)
      flash :success, t('flash.job_rerun')
    end
    redirect "/jobs/#{params[:id]}"
  end

  post '/jobs/:id/kill' do
    dl = Download.first(id: params[:id].to_i)
    if dl && dl.killable?
      dl.mark_failed!('Killed by user')
      dl.update(log: [dl.log, "[#{Time.now.iso8601}] Killed by user"].compact.join("\n"))
      flash :success, t('flash.job_killed')
    end
    redirect "/jobs/#{params[:id]}"
  end

  post '/jobs/:id/delete' do
    dl = Download.first(id: params[:id].to_i)
    dl&.destroy
    flash :success, t('flash.job_deleted')
    redirect '/jobs'
  end

  # ------------------------------------------------------------------
  # Log
  # ------------------------------------------------------------------
  get '/log' do
    scope = Download.eager(:bank)
    scope = scope.where(bank_id: params[:bank_id].to_i)       unless params[:bank_id].to_s.empty?
    scope = scope.where(status: params[:status])              unless params[:status].to_s.empty?
    scope = scope.where { date >= Date.parse(params[:from]) } unless params[:from].to_s.empty?
    scope = scope.where { date <= Date.parse(params[:to]) }   unless params[:to].to_s.empty?

    @filter_bank_id = params[:bank_id]
    @filter_status  = params[:status]
    @filter_from    = params[:from]
    @filter_to      = params[:to]
    @banks          = Bank.all
    @downloads      = scope.order(Sequel.desc(:created_at)).limit(500).all
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
  # Email Senders
  # ------------------------------------------------------------------
  get '/email_senders' do
    @email_senders = EmailSender.eager(:bank).order(:sender_name).all
    @banks         = Bank.all
    erb :email_senders
  end

  post '/email_senders' do
    es = EmailSender.new(
      sender_name:  params[:sender_name],
      sender_email: params[:sender_email],
      bank_id:      params[:bank_id].to_s.empty? ? nil : params[:bank_id].to_i,
      active:       true,
      created_at:   Time.now,
      updated_at:   Time.now
    )
    if es.valid? && es.save
      flash :success, t('flash.email_sender_added', name: es.sender_name)
    else
      flash :error, t('flash.email_sender_error', errors: es.errors.full_messages.join(', '))
    end
    redirect '/email_senders'
  end

  post '/email_senders/:id/toggle' do
    es = EmailSender[params[:id].to_i]
    if es
      es.update(active: !es.active, updated_at: Time.now)
      flash :success, t('flash.email_sender_toggled', name: es.sender_name)
    end
    redirect '/email_senders'
  end

  post '/email_senders/:id/delete' do
    es = EmailSender[params[:id].to_i]
    if es
      es.destroy
      flash :success, t('flash.email_sender_deleted', name: es.sender_name)
    end
    redirect '/email_senders'
  end

  # ==================================================================
  # Mobile  — /mobile
  # ==================================================================
  get '/mobile' do
    redirect '/mobile/'
  end

  get '/mobile/' do
    today             = Date.today
    @recent_downloads = Download.recent(10).eager(:bank).all
    @banks            = Bank.all
    @today_success    = Download.where(status: 'success', date: today).count
    @today_failed     = Download.where(status: 'failed',  date: today).count
    @today_running    = Download.where(status: 'running', date: today).count
    erb :'mobile/home', layout: :'mobile/layout'
  end

  get '/mobile/jobs' do
    scope = Download.eager(:bank)
    scope = scope.where(status: params[:status]) unless params[:status].to_s.empty?
    scope = scope.where(date: Date.parse(params[:date])) unless params[:date].to_s.empty?
    @filter_date   = params[:date] || Date.today.to_s
    @filter_status = params[:status]
    @downloads     = scope.order(Sequel.desc(:created_at)).all
    erb :'mobile/jobs', layout: :'mobile/layout'
  end

  post '/mobile/jobs/run' do
    Thread.new { DownloadJob.run(date: Date.today) }
    flash :success, t('flash.job_triggered')
    redirect '/mobile/jobs'
  end

  get '/mobile/log' do
    scope = Download.eager(:bank)
    scope = scope.where(bank_id: params[:bank_id].to_i)       unless params[:bank_id].to_s.empty?
    scope = scope.where(status: params[:status])              unless params[:status].to_s.empty?
    scope = scope.where { date >= Date.parse(params[:from]) } unless params[:from].to_s.empty?
    scope = scope.where { date <= Date.parse(params[:to]) }   unless params[:to].to_s.empty?
    @filter_bank_id = params[:bank_id]
    @filter_status  = params[:status]
    @filter_from    = params[:from]
    @filter_to      = params[:to]
    @banks          = Bank.all
    @downloads      = scope.order(Sequel.desc(:created_at)).limit(200).all
    erb :'mobile/log', layout: :'mobile/layout'
  end

  get '/mobile/banks' do
    @banks = Bank.all
    erb :'mobile/banks', layout: :'mobile/layout'
  end

  post '/mobile/banks' do
    bank = Bank.new(
      name:             params[:name],
      sftp_host:        params[:sftp_host],
      sftp_port:        params[:sftp_port].to_i,
      sftp_remote_path: params[:sftp_remote_path] || '/',
      sftp_username:    params[:sftp_username],
      sftp_password:    params[:sftp_password],
      ruler:            params[:ruler],
      parser:           params[:parser],
      created_at:       Time.now,
      updated_at:       Time.now
    )
    if bank.valid? && bank.save
      flash :success, t('flash.bank_added', name: bank.name)
    else
      flash :error, t('flash.bank_error', errors: bank.errors.full_messages.join(', '))
    end
    redirect '/mobile/banks'
  end

  get '/mobile/settings' do
    @settings = Setting.order(:key).all
    erb :'mobile/settings', layout: :'mobile/layout'
  end

  post '/mobile/settings' do
    (params[:settings] || {}).each do |key, value|
      Setting.set(key, value)
    end
    flash :success, t('flash.settings_saved')
    redirect '/mobile/settings'
  end

  get '/mobile/email_senders' do
    @email_senders = EmailSender.eager(:bank).order(:sender_name).all
    @banks         = Bank.all
    erb :'mobile/email_senders', layout: :'mobile/layout'
  end

  post '/mobile/email_senders' do
    es = EmailSender.new(
      sender_name:  params[:sender_name],
      sender_email: params[:sender_email],
      bank_id:      params[:bank_id].to_s.empty? ? nil : params[:bank_id].to_i,
      active:       true,
      created_at:   Time.now,
      updated_at:   Time.now
    )
    if es.valid? && es.save
      flash :success, t('flash.email_sender_added', name: es.sender_name)
    else
      flash :error, t('flash.email_sender_error', errors: es.errors.full_messages.join(', '))
    end
    redirect '/mobile/email_senders'
  end

  post '/mobile/email_senders/:id/toggle' do
    es = EmailSender[params[:id].to_i]
    if es
      es.update(active: !es.active, updated_at: Time.now)
      flash :success, t('flash.email_sender_toggled', name: es.sender_name)
    end
    redirect '/mobile/email_senders'
  end

  post '/mobile/email_senders/:id/delete' do
    es = EmailSender[params[:id].to_i]
    if es
      es.destroy
      flash :success, t('flash.email_sender_deleted', name: es.sender_name)
    end
    redirect '/mobile/email_senders'
  end

  # ==================================================================
  # JSON API  — /api/v1
  # ==================================================================
  before '/api/*' do
    content_type :json
    @api_start_time  = Time.now
    if request.content_type&.include?('application/json')
      body = request.body.read
      @json_params = body.empty? ? {} : JSON.parse(body, symbolize_names: true)
    else
      @json_params = {}
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
  # GET /api/v1/downloads
  # ------------------------------------------------------------------
  get '/api/v1/downloads' do
    scope = Download.eager(:bank).order(Sequel.desc(:created_at))
    scope = scope.where(status:  params[:status])            unless params[:status].to_s.empty?
    scope = scope.where(bank_id: params[:bank_id].to_i)      unless params[:bank_id].to_s.empty?
    scope = scope.where(date:    Date.parse(params[:date]))  unless params[:date].to_s.empty?

    paginate(scope).all.map { |dl| serialize_download(dl) }.to_json
  end

  # ------------------------------------------------------------------
  # GET /api/v1/downloads/:id
  # ------------------------------------------------------------------
  get '/api/v1/downloads/:id' do
    dl = Download.eager(:bank).first(id: params[:id].to_i)
    api_error(404, 'Download not found') unless dl
    serialize_download(dl).to_json
  end

  # ------------------------------------------------------------------
  # POST /api/v1/downloads  — enqueue a download for a bank
  # ------------------------------------------------------------------
  post '/api/v1/downloads' do
    p = json_body
    bank_id  = (p[:bank_id] || params[:bank_id]).to_i
    date_str = p[:date] || params[:date]
    date     = date_str ? Date.parse(date_str.to_s) : Date.today

    api_error(422, 'bank_id is required') if bank_id.zero?

    bank = Bank.first(id: bank_id)
    api_error(404, 'Bank not found') unless bank

    if Download.where(bank_id: bank.id, date: date).count > 0
      api_error(409, "Download already exists for bank #{bank_id} on #{date}")
    end

    dl = Download.create(
      bank_id:    bank.id,
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
      banks_count:     Bank.count,
      last_success: last_success ? {
        id:           last_success.id,
        bank_id:      last_success.bank_id,
        date:         last_success.date.to_s,
        completed_at: last_success.completed_at&.iso8601
      } : nil,
      last_failure: last_failure ? {
        id:            last_failure.id,
        bank_id:       last_failure.bank_id,
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
