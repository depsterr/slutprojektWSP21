#!/usr/bin/env ruby

# Change directory to script to make sure execution is done in the right enviorment
Dir.chdir(File.dirname(__FILE__))

require 'sinatra'
require 'slim'

require_relative 'model.rb'
require_relative 'view.rb'

enable :sessions

# TODO:
#  - [x] finish model.rb TODOs
#  - [x] Home/Boards page
#  - [x] Board/Threads page
#  - [x] Thread/Posts page
#  - [x] Error page
#  - [x] Register page
#  - [x] Log in page
#  - [ ] REST routes för att interagera med DataBase klassen
#        (skulle kunna använda en lookup table approach?)
#  - [ ] User profile page
#  - [ ] User options
#  - [ ] Styling
#  - [ ] Extra model.rb todos

before do
  session[:user_id] = 0 if session[:user_id].nil?
  unless session[:user_id] == 0
    if session[:user] == nil
      session[:user] = DataBase.new.get_user(session[:user_id])
    end
  else
    session[:user] = nil
  end
end

get '/' do
  redirect to('/home')
end

get '/error' do
  error = session[:error]
  session.delete(:error)
  slim :error, locals: { error: error }
end

get '/home' do
  db = DataBase.new
  slim :boards, locals: { boards: db.get_boards }
end

get '/board/:board' do
  db = DataBase.new
  threads = db.get_threads(params[:board].to_i)
  handle_error(threads)
  slim :threads, locals: { threads: threads }
end

get '/thread/:thread' do
  db = DataBase.new
  posts = db.get_posts(params[:thread].to_i)
  handle_error(posts)
  slim :posts, locals: { posts: posts }
end

get '/register' do
  slim :register
end

get '/login' do
  slim :login
end

post '/action/:type/:action' do
  db = DataBase.new
  case params[:type]
  when "user"
    case params[:action]
    when "register"
      result = db.register(request["username"],
                               request["password"],
                               request["repeat"],
                               request.ip)
      handle_error(result)
      session[:user_id] = result
      redirect to('/home')
    when "login"
      result = db.login(request["username"],
                               request["password"],
                               request.ip)
      handle_error(result)
      session[:user_id] = result
      redirect to('/home')
    when "logout"
      session.destroy
      redirect to('/home')
    end
  end
  error_with('BADREQ')
end
