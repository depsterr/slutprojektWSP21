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
#  - [ ] Home/Boards page
#  - [ ] Board/Threads page
#  - [ ] Thread/Posts page
#  - [ ] Error page
#  - [ ] REST routes för att interagera med DataBase klassen
#        (skulle kunna använda en lookup table approach?)
#  - [ ] Register page
#  - [ ] Log in page
#  - [ ] User profile page
#  - [ ] User options

before do
  session[:user_id] = 0 if session[:user_id].nil?
end

get '/' do
  redirect to('/home')
end

get '/error' do
  error = session[:error]
  p error
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
  if threads.class == String
    session[:error] = threads
    p threads
    redirect to('/error')
  end
  slim :threads, locals: { threads: threads }
end

get '/thread/:thread' do
  db = DataBase.new
  posts = db.get_posts(params[:thread].to_i)
  if posts.class == String
    session[:error] = posts
    p posts
    redirect to('/error')
  end
  slim :posts, locals: { posts: posts }
end
