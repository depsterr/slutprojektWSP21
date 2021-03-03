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
#  - [x] REST routes för att interagera med DataBase klassen
#  - [x] User profile page
#  - [x] User options
#  - [ ] Watch
#  - [ ] Mark as read
#  - [ ] Editing
#  - [ ] Reporting
#  - [ ] Extra model.rb todos

# Set up user_id and user
before do
  db = DataBase.new
  session[:user_id] = 0 if session[:image].nil?
  unless session[:user_id] == 0
    session[:user] = db.get_user(session[:user_id])
  else
    session[:user] = nil
  end
  session[:image] = {} if session[:image].nil?
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

get '/user/:user' do
  db = DataBase.new
  user = db.get_user(params[:user].to_i)
  handle_error(user)
  image = db.get_image(user['UserId'])
  handle_error(image)
  slim :user, locals: { user: user, image: image }
end

get '/user/:user/edit' do
  if session[:user_id] != params[:user].to_i
    redirect to("/user/#{params[:user]}")
  end
  db = DataBase.new
  user = db.get_user(params[:user].to_i)
  handle_error(user)
  image = db.get_image(user['UserId'])
  handle_error(image)
  slim :edit_user, locals: { user: user, image: image }
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
    when "edit"
      if defined?(params["file"]) && !params["file"].nil? && !params["file"].nil? 
        filename = params["file"]["tempfile"].path
      else
        filename = nil
      end
      result = db.update_user(session[:user_id], {
        name: request['username'],
        image_path: filename,
        footer: request['footer']
      })
      handle_error(result)
      redirect to("/user/#{session[:user_id]}")
    when "logout"
      session.destroy
      redirect to('/home')
    end
  when "board"
    case params[:action]
    when "new"
      result = db.create_board(request["title"],
                               session[:user_id])
      handle_error(result)
      redirect to("/board/#{result}")
    when "delete"
      result = db.delete_board(request["board_id"],
                               session[:user_id])
      handle_error(result)
      redirect to('/home')
    end
  when "thread"
    case params[:action]
    when "new"
      thread = db.create_thread(request["title"],
                                request["board_id"].to_i,
                                session[:user_id])
      handle_error(thread)
      post = db.create_post(request["content"],
                              thread,
                              session[:user_id])

      # Remove already created thread
      if error? post
        db.delete_thread(thread, session[:user_id])
        error_str(post)
      end

      redirect to("/thread/#{thread}")
    when "delete"
      result = db.delete_thread(request["thread_id"],
                                session[:user_id])
      handle_error(result)
      redirect to("/board/#{request["board_id"]}")
    end
  when "post"
    case params[:action]
    when "new"
      result = db.create_post(request["content"],
                              request["thread_id"],
                              session[:user_id])

      handle_error(result)
      redirect to("/thread/#{request["thread_id"]}")
    when "delete"
      result = db.delete_post(request["post_id"],
                              session[:user_id])
      handle_error(result)
      if result
        redirect to("/thread/#{request["thread_id"]}")
      else
        redirect to("/board/#{request["board_id"]}")
      end
    end
  end
  error_with('BADREQ')
end
