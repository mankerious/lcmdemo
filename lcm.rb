require 'bundler/setup'
require 'gooddata'
require 'sinatra'
require 'slim'
require 'sinatra/base'
require 'active_support/all'
require_relative 'credentials'

# Projects are set in the credentials file but in the future will be customizable through the settings page
VALID_PROJECTS = [MASTERPROJECT1, MASTERPROJECT2]



app_state = {
  segments: []
}

# Enable Logging
# configure do
#     enable :logging
#     file = File.new("#{settings.root}/log/#{settings.environment}.log", 'a+')
#     file.sync = true
#     use Rack::CommonLogger, file    
# end
  
get '/' do 
  # pp app_state
  client = GoodData.connect(LOGIN, PASSWORD)
  # Take all projects created in this domain
  # @projects = client.projects.pselect {|p| client.get(p.uri)['project']['content']['authorizationToken'] == TOKEN}
  @projects = VALID_PROJECTS.pmap { |pid| client.projects(pid) }
  slim :index
end

get '/start_new_demo' do 
  # pp app_state
  app_state = {
   segments: []
  }
  client = GoodData.connect(LOGIN, PASSWORD)
  domain = client.domain(DOMAIN)
  domain.segments.peach do |s|
    s.delete(force: true)
  end
  "DONE"
    client = GoodData.connect(LOGIN, PASSWORD)
    @projects = VALID_PROJECTS.pmap { |pid| client.projects(pid) }
  slim :index
end

post '/index' do
  client = GoodData.connect(LOGIN, PASSWORD)
  domain = client.domain(DOMAIN)
  begin
  @master_project = client.projects(params[:projectid])
  @segment = domain.create_segment(segment_id: params[:segment_name], master_project: @master_project)
  app_state[:segments] << { segment_id: params[:segment_name], master_project_id: params[:projectid] }
  rescue RestClient::BadRequest => e
    errors = true
  end
  
  unless errors
    redirect "/service_projects"
  else
    @projects = VALID_PROJECTS.pmap { |pid| client.projects(pid) }
    @errors = "The segment name is already in use or the master is linked to a different segment. Please use a different name or restart the demo."
    slim :index
  end
end

get '/service_projects' do
  client = GoodData.connect(LOGIN, PASSWORD)
  domain = client.domain(DOMAIN)
  current_segment = app_state[:segments].last
  @segment = domain.segments(current_segment[:segment_id])
  @master_project = client.projects(current_segment[:master_project_id])
  slim :service_projects
end

post '/service_projects' do
  client = GoodData.connect(LOGIN, PASSWORD)
  domain = client.domain(DOMAIN)

  current_segment = app_state[:segments].last

  # Here we could spin the service projects
  # service_project = client.create_project(title: params[:service_project_name], auth_token: TOKEN)
  # current_segment[:service_project] = service_project.pid
  current_segment[:service_project] = params[:service_project_name]

  if params.key?('button_1')
    redirect '/'
  else
    redirect '/provision_clients'
  end
end

get '/provision_clients' do
  puts app_state
  @segments = app_state[:segments]
  slim :provision_clients
end

post '/provision_clients' do
  client = GoodData.connect(LOGIN, PASSWORD)
  domain = client.domain(DOMAIN)

  stuff = params['client_name'].zip(params['segment_id'])
    .map {|client_id, segment_id| {client_id: client_id, segment_id: segment_id}}
    .reject { |thing| thing[:client_id].blank? }
  
  app_state[:clients] = stuff.pmap do |stuff|
    stuff[:project] = domain.segments(stuff[:segment_id]).master_project.clone(:title => stuff[:client_id], auth_token: TOKEN).pid
    stuff
  end
  app_state[:clients].each do |s|
    domain.segments(s[:segment_id]).create_client(id: s[:client_id], project: client.projects(s[:project]))
  end
  redirect '/confirmation'
end

get '/confirmation' do
  client = GoodData.connect(LOGIN, PASSWORD)
  domain = client.domain(DOMAIN)

  @projects = app_state[:clients].pmap { |c| {segment: domain.segments(c[:segment_id]), project: client.projects(c[:project])}}
  slim :confirmation
end


