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
#  - [x] Highlight unread posts in threads
#  - [x] Sticky
#  - [x] Unread posts/notification page
#  - [x] Fix REST routes
#  - [x] Editing
#  - [x] Reporting
#  - [ ] Extra model.rb todos

# Set up user_id and user
before do
  db = DataBase.new
  session[:user_id] = 0 if session[:user_id].nil?
  unless session[:user_id] == 0
    session[:user] = db.get_user(session[:user_id])
    session[:image] = db.get_image(session[:user_id])
    session[:unread] = db.get_unread(session[:user_id]).length
  end
end

# Redirect traffic to / to the home route
get '/' do
  redirect to('/home')
end

# Displays the session error string and then resets
# the session error string.
get '/error' do
  error = session[:error]
  session.delete(:error)
  slim :error, locals: { error: error }
end

# The homepage, displays the current boards
# @see DataBase.get_boards
get '/home' do
  db = DataBase.new
  slim :boards, locals: { boards: db.get_boards }
end

# Show unread threads
# @see DataBase.get_unread
get '/unread' do
  db = DataBase.new
  watches = []
  unread = []
  if logged_in?
    watches = db.get_watched(session[:user_id])
    unread  = db.get_unread(session[:user_id])
  end
  slim :unread, locals: { watches: watches, unread: unread }
end

# Displays the threads of a board
# @param [Integer] :board, board to grab threads from
# @see DataBase.get_threads
# @see DataBase.get_watched
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

# Displays the posts of the thread with thread_id :thread
# @see DataBase.get_posts
get '/thread/:thread' do
  db = DataBase.new
  posts = db.get_posts(params[:thread].to_i)
  handle_error(posts)
  unreads = []
  if logged_in?
    unreads = db.get_unread(session[:user_id])
    result = db.mark_thread_read(params[:thread],
                                 session[:user_id])
    handle_error(result)
  end
  slim :posts, locals: { posts: posts, unreads: unreads.map { |unread| unread['PostId'] } }
end

# Displays a users page
# @param [Integer] :user, user who's page to display
# @see DataBase.get_user
# @see DataBase.get_image
get '/user/:user' do
  db = DataBase.new
  user = db.get_user(params[:user].to_i)
  handle_error(user)
  image = db.get_image(user['UserId'])
  handle_error(image)
  slim :user, locals: { user: user, image: image }
end

# Edit page for as user
# @param [Integer] :user, user who's page to edit
# @see DataBase.get_user
# @see DataBase.get_image
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

# Edit page for posts
# @param [Integer] :post_id, post to edit
# @see DataBase.get_user
# @see DataBase.get_post
get '/post/:post_id/edit' do
  db = DataBase.new
  post = db.get_post params[:post_id].to_i
  user = db.get_user session[:user_id]
  slim :edit_post, locals: { post: post, user: user }
end

# Registration page
get '/register' do
  slim :register
end

# Login page
get '/login' do
  slim :login
end

# This handles requests from other routes.
# This route covers all actions which do not operate on a specific
# object and therefore do not need to specify and id.
# @param [String] :type, the type of oject to act upon (board, user, thread, post)
# @param [String] :action, the action to take on said object
# @see DataBase#register
# @see DataBase#login
# @see DataBase#update_user
# @see DataBase#create_board
# @see DataBase#create_thread
# @see DataBase#delete_thread
# @see DataBase#create_post
# @see DataBase#delete_post
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

# This route covers all actions which operate on a specific board.
# @param [String] :board_id, the id of the board to act upon
# @param [String] :action, the action to take on said object
# @see DataBase#delete_board
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


# This route covers all actions which operate on a specific thread.
# @param [String] :thread_id, the id of the thread to act upon
# @param [String] :action the action to take on said object
# @see DataBase#update_sticky_thread
# @see DataBase#delete_thread
# @see DataBase#start_watching
# @see DataBase#stop_watching
# @see DataBase#mark_thread_read
post '/action/thread/:thread_id/:action' do
  db = DataBase.new
  case params[:action]
  when "sticky"
    result = db.update_sticky_thread(params[:thread_id],
                              params["sticky"].to_i,
                              session[:user_id])
    handle_error(result)
    redirect to("/board/#{request["board_id"]}")
  when "delete"
    result = db.delete_thread(params[:thread_id],
                              session[:user_id])
    handle_error(result)
    redirect to("/board/#{request["board_id"]}")
  when "watch"
    result = db.start_watching(params[:thread_id],
                               session[:user_id])
    handle_error(result)
    redirect to("/board/#{request["board_id"]}") unless request["unread"] == "true"
    redirect to("/unread")
  when "unwatch"
    result = db.stop_watching(params[:thread_id],
                              session[:user_id])
    handle_error(result)
    redirect to("/board/#{request["board_id"]}") unless request["unread"] == "true"
    redirect to("/unread")
  when "mark_read"
    result = db.mark_thread_read(params[:thread_id],
                                 session[:user_id])
    handle_error(result)
    redirect to("/board/#{request["board_id"]}") unless request["unread"] == "true"
    redirect to("/unread")
  end
  error_with('BADREQ')
end

# This route covers all actions which operate on a specific post.
# @param [String] :post_id, the id of the post to act upon
# @param [String] :action, the action to take on said object
# @see DataBase#delete_post
# @see DataBase#report
# @see DataBase#edit_post
post '/action/post/:post_id/:action' do
  db = DataBase.new
  case params[:action]
  when "delete"
    result = db.delete_post(params[:post_id],
                            session[:user_id])
    handle_error(result)
    redirect to("/thread/#{request["thread_id"]}") if result
    redirect to("/board/#{request["board_id"]}")
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
