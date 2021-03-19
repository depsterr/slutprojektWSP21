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
#  - [x] Watch
#  - [x] Mark as read
#  - [ ] Highlight unread posts in threads
#  - [ ] Unread posts/notification page
#  - [ ] Fix REST routes
#  - [ ] Editing
#  - [ ] Reporting
#  - [ ] Extra model.rb todos

# Set up user_id and user
before do
  db = DataBase.new
  session[:user_id] = 0 if session[:user_id].nil?
  unless session[:user_id] == 0
    session[:user] = db.get_user(session[:user_id])
    session[:image] = db.get_image(session[:user_id])
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
  watches = []
  unread = []
  if logged_in?
    watches = db.get_watched(session[:user_id])
    unread  = db.get_unread(session[:user_id])
  end
  slim :threads, locals: { threads: threads, watches: watches, unread: unread }
end

get '/thread/:thread' do
  db = DataBase.new
  posts = db.get_posts(params[:thread].to_i)
  handle_error(posts)
  if logged_in?
    result = db.mark_thread_read(params[:thread],
                                 session[:user_id])
    handle_error(result)
  end
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

get '/post/:post_id/edit' do
  db = DataBase.new
  post = db.get_post params[:post_id].to_i
  user = db.get_user session[:user_id]
  slim :edit_post, locals: { post: post, user: user }
end

get '/register' do
  slim :register
end

get '/login' do
  slim :login
end

#### Actions which do not need an id ###
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
    end
  when "post"
    case params[:action]
    when "new"
      result = db.create_post(request["content"],
                              request["thread_id"],
                              session[:user_id])

      handle_error(result)
      redirect to("/thread/#{request["thread_id"]}")
    end
  end
  error_with('BADREQ')
end

#### Actions which do need an id ###
post '/action/board/:board_id/:action' do
  db = DataBase.new
  case params[:action]
  when "delete"
    result = db.delete_board(params[:board_id],
                             session[:user_id])
    handle_error(result)
    redirect to('/home')
  end
  error_with('BADREQ')
end
post '/action/thread/:thread_id/:action' do
  db = DataBase.new
  case params[:action]
  when "delete"
    result = db.delete_thread(params[:thread_id],
                              session[:user_id])
    handle_error(result)
    redirect to("/board/#{request["board_id"]}")
  when "watch"
    result = db.start_watching(params[:thread_id],
                               session[:user_id])
    handle_error(result)
    redirect to("/board/#{request["board_id"]}")
  when "unwatch"
    result = db.stop_watching(params[:thread_id],
                              session[:user_id])
    handle_error(result)
    redirect to("/board/#{request["board_id"]}")
  when "mark_read"
    result = db.mark_thread_read(params[:thread_id],
                                 session[:user_id])
    handle_error(result)
    redirect to("/board/#{request["board_id"]}")
  end
  error_with('BADREQ')
end

post '/action/post/:post_id/:action' do
  db = DataBase.new
  case params[:action]
  when "delete"
    result = db.delete_post(params[:post_id],
                            session[:user_id])
    handle_error(result)
    if result
      redirect to("/thread/#{request["thread_id"]}")
    else
      redirect to("/board/#{request["board_id"]}")
    end
  when "report"
    result = db.report(params[:post_id])
    handle_error(result)
    redirect to("/thread/#{request["thread_id"]}")
  when "edit"
    result = db.edit_post(request["content"],
                          params[:post_id],
                          session[:user_id])
    handle_error(result)
    redirect to("/thread/#{request["thread_id"]}")
  end
  error_with('BADREQ')
end
