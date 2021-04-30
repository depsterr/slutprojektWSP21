require 'sinatra'
require 'digest'
require 'bcrypt'
require 'sanitize'
require 'sqlite3'
require 'fileutils'

require_relative 'view.rb'

# Sinatra helpers
helpers do
  # get the name of the current page
  # @return [String] the name of the current page
  def page_name
    if defined? docname
      docname
    else
      $sitename
    end
  end

  # Translate a local image filepath into it's absolute filepath
  # on the web. This also makes sure that the default profile
  # picture is used if none is found.
  # @param path [String] local filepath
  # @return [String] web filepath
  def local_to_web_path(path)
    return "/img/#{File.basename(path)}" unless path.nil?
    "/img/default.jpg"
  end

  # Redirect to error with error string
  # @param str [String] error message
  def error_str(str)
    session[:error] = str
    redirect to('/error')
  end

  # Redirect to error with error code 
  # @param errorcode [String] key for $error hash
  def error_with(errorcode)
    error_str($error[errorcode])
  end

  # See if val is error
  # @param val [Any] value to compare against an error
  # @return [Bool] true if val is a String
  def error?(val)
    val.class == String
  end

  # Handle return value. Does nothing if val is not a string
  # if val is a string then error with that string.
  # @param val [Any] value to handle error for
  def handle_error(val)
    error_str(val) if error? val
  end

  # See if user is logged in
  # @return [Bool]
  def logged_in?
    session[:user_id] > 0 && !session[:user].nil?
  end
  
  # See if user is admin
  # @return [Bool]
  def admin?
    logged_in? && session[:user]['UserPrivilege'] > 0
  end

  # Set up user session
  def set_up_session
    db = DataBaseHandler.new
    session[:user_id] = 0 if session[:user_id].nil?
    unless session[:user_id] == 0
      session[:user] = db.get_user(session[:user_id])
      session[:image] = db.get_image(session[:user_id])
      session[:unread] = db.get_unread(session[:user_id]).length
    end
  end

  # Get the current error and then clear it
  # @return [String] current error
  def get_error
    error = session[:error]
    session.delete(:error)
    return error
  end

end

# Exit program printing an error message
# @param msg [String] message to print before exit
def die(msg)
  STDERR.puts(msg)
  exit 1
end

# Could use a report system which adds posts to unread for
# all users with a privilege level over 0.

# This class is used to abstract away database operations.
# Dates are stored as integers using unix epoch.
# Booleans are stored as 1/0 integers.
# User privelege levels:
#  - 0: normal (logged in) user
#  - 1: admin
# TODO:
#  - [x] Log in
#  - [x] Register
#  - [x] Delete User
#  - [x] Create/Delete Board
#  - [x] Create/Delete Thread
#  - [x] Create/Delete Post
#  - [x] Sticky Thread
#  - [x] [Un]watch Thread
#  - [x] Get unread
#  - [x] Mark unread read
#  - [x] Edit user settings
#  - [x] Return nil to be consistent (do what docs say)
#  - [x] Strip strings
#  - [x] Sanitize strings (see https://github.com/rgrove/sanitize)
#  - [x] Get boards method
#  - [x] Get threads method
#  - [x] Get posts method
#  - [x] Image handling
# DO IF YOU HAVE THE TIME:
#  - [ ] Let user edit most fields
class DataBaseHandler
  # Create a new DataBaseHandler connection
  # @param path [String] the path to the database file
  # @return [DataBaseHandler]
  public def initialize(path = "db/database.sqlite")
    raise TypeError if path.class != String
    @db = SQLite3::Database.new path
    @db.foreign_keys = true
    die "Unable to set foreign keys pragma" unless @db.foreign_keys == true
    @db.results_as_hash = true
  end

  # Setup all tables
  # @return [Nil]
  public def init
    init_table("Image", "ImageId INTEGER PRIMARY KEY AUTOINCREMENT,"\
      "ImageMD5 STRING NOT NULL,"\
      "ImageFilepath STRING NOT NULL")

    init_table("User", "UserId INTEGER PRIMARY KEY AUTOINCREMENT,"\
      "UserName STRING NOT NULL,"\
      "UserFooter STRING NOT NULL,"\
      "UserPrivilege INTEGER NOT NULL,"\
      "UserRegistrationDate INTEGER NOT NULL,"\
      "ImageId INTEGER NOT NULL,"\
      "FOREIGN KEY(ImageId) REFERENCES Image(ImageId)")

    init_table("Hash", "HashId INTEGER PRIMARY KEY AUTOINCREMENT,"\
      "Hash STRING NOT NULL,"\
      "UserId INTEGER NOT NULL,"\
      "FOREIGN KEY(UserId) REFERENCES User(UserId) ON DELETE CASCADE")

    init_table("Board", "BoardId INTEGER PRIMARY KEY AUTOINCREMENT,"\
      "BoardName STRING NOT NULL,"\
      "BoardCreationDate INTEGER NOT NULL,"\
      "UserId INTEGER NOT NULL,"\
      "FOREIGN KEY(UserId) REFERENCES User(UserId)")

    init_table("Thread", "ThreadId INTEGER PRIMARY KEY AUTOINCREMENT,"\
      "ThreadName STRING NOT NULL,"\
      "ThreadCreationDate INTEGER NOT NULL,"\
      "ThreadStickied INTEGER NOT NULL,"\
      "BoardId INTEGER NOT NULL,"\
      "UserId INTEGER NOT NULL,"\
      "FOREIGN KEY(UserId) REFERENCES User(UserId),"\
      "FOREIGN KEY(BoardId) REFERENCES Board(BoardId) ON DELETE CASCADE")

    init_table("Post", "PostId INTEGER PRIMARY KEY AUTOINCREMENT,"\
      "PostContent STRING NOT NULL,"\
      "PostCreationDate INTEGER NOT NULL,"\
      "UserId INTEGER NOT NULL,"\
      "ThreadId INTEGER NOT NULL,"\
      "FOREIGN KEY(UserId) REFERENCES User(UserId),"\
      "FOREIGN KEY(ThreadId) REFERENCES Thread(ThreadId) ON DELETE CASCADE")

    # relation tables
    init_table("UserWatchingThread", "UserId INTEGER NOT NULL,"\
      "ThreadId INTEGER NOT NULL,"\
      "FOREIGN KEY(UserId) REFERENCES User(UserId) ON DELETE CASCADE,"\
      "FOREIGN KEY(ThreadId) REFERENCES Thread(ThreadId) ON DELETE CASCADE")

    init_table("UserUnreadPost", "UserId INTEGER NOT NULL,"\
      "PostId INTEGER NOT NULL,"\
      "FOREIGN KEY(UserId) REFERENCES User(UserId) ON DELETE CASCADE,"\
      "FOREIGN KEY(PostId) REFERENCES Post(PostId) ON DELETE CASCADE")

    image_file = "./public/img/default.jpg"
    md5_hash = Digest::MD5.hexdigest(File.read(image_file))

    @db.execute("INSERT INTO Image(ImageMD5, ImageFilepath) VALUES(?,?)",
                md5_hash, image_file)

    nil
  end

  # Authenticate a user login
  # @param user [String] the username
  # @param pass [String] the password
  # @param identifier [String] identifier used to stop spam
  #   attempts, (probably the IP address)
  # @return [Integer,String] on sucess returns user id, otherwise
  #   returns error string.
  public def login(user, pass, identifier)

    return $error['BADREQ'] if user.nil? || pass.nil? || identifier.nil?

    user.strip!
    pass.strip!

    return $error['TIMEOUT'] unless Validator.timeout? identifier

    result = @db.execute("SELECT * FROM User WHERE UserName=?", user)
    return $error['NOUSER'] if result.empty?

    user_id = result.first["UserId"]
    user_digest = @db.execute("SELECT Hash FROM Hash WHERE UserId=?", user_id).first["Hash"]

    return $error['WRONGPASS'] unless BCrypt::Password.new(user_digest) == pass

    return user_id

  end

  # Register a new user
  # @param user [String] the username
  # @param pass [String] the password
  # @param identifier [String] identifier used to stop spam
  #   attempts, (probably the IP address)
  # @return [Integer,String] on sucess returns user id, otherwise
  #   returns error string.
  public def register(user, pass, repeat_pass, identifier)

    return $error['BADREQ'] if user.nil? || pass.nil? || repeat_pass.nil? || identifier.nil?

    user.strip!
    pass.strip!
    repeat_pass.strip!
    
    return $error['TIMEOUT'] unless Validator.timeout? identifier
    return $error['NOMATCH'] unless pass == repeat_pass
    return $error['BADUSER'] unless Validator.username? user
    return $error['BADPASS'] unless Validator.password? pass

    result = @db.execute("SELECT * FROM User WHERE UserName=?", user)
    return $error['USERTAKEN'] unless result.empty?

    pass_digest = BCrypt::Password.create(pass)
    @db.execute("INSERT INTO User(UserName, UserFooter, UserPrivilege, UserRegistrationDate, ImageId)"\
      "VALUES(?,?,?,?,1)", user, "I'm new here!", 0, Time.now.to_i)

    id = @db.execute("SELECT UserId FROM User WHERE UserName=?", user).first["UserId"]

    @db.execute("INSERT INTO Hash(Hash, UserId) VALUES(?,?)", pass_digest, id)

    return id

  end

  # Update user settings. Any argument set to nil or an
  # empty string will not be updated.
  # @param caller_id [Integer] issuer of call
  # @param options [Hash] contains all information to update.
  # @option options [String] :name new username
  # @option options [String] :footer new footer
  # @option options [String] :image path to new image
  # @return [nil,String] returns error string on failure
  public def update_user(caller_id, options)

    return $error['BADREQ'] if caller_id.nil? || options.nil?

    user = get_user(caller_id)
    return $error['NOUSER'] if user.nil?

    unless options[:name].nil?
      name = options[:name].strip
      return $error['BADUSER'] unless Validator.username? name

      result = @db.execute("SELECT * FROM User WHERE UserName=?", name)
      if result.empty?
        @db.execute("UPDATE User SET UserName=? WHERE UserId=?", name, caller_id)
      else
        return $error['USERTAKEN'] if result['UserId'] != caller_id
      end
    end

    unless options[:footer].nil?
      footer = Validator.sanitize_content(options[:footer].strip)
      return $error['BADCONTENT'] if footer.empty?
      @db.execute("UPDATE User SET UserFooter=? WHERE UserId=?", footer, caller_id)
    end

    unless options[:image_path].nil?
      new_image = options[:image_path]
      old_image = @db.execute("SELECT Image.ImageId,ImageFilepath,ImageMD5 FROM User INNER JOIN Image WHERE "\
                              "User.ImageId = Image.ImageId AND UserId=?", caller_id).first

      # Check if identical image exists
      md5_hash = Digest::MD5.hexdigest(File.read(new_image)) 

      # Images with same digest
      matches = @db.execute("SELECT * FROM Image WHERE ImageMD5=?", md5_hash)

      if matches.empty?
        # Image is new
        # Move image into public folder and add it to database
        FileUtils.mv(new_image, "./public/img/#{File.basename(new_image)}")
        @db.execute("INSERT INTO Image(ImageMD5, ImageFilepath) VALUES(?,?)", md5_hash,
                    "./public/img/#{File.basename(new_image)}")

        # Update user image
        image_id = @db.execute("SELECT ImageId FROM Image WHERE ImageMD5=?", md5_hash).first['ImageId']
        @db.execute("UPDATE User SET ImageId=? WHERE UserId=?", image_id, caller_id)

        # Delete old profile picture if unused
        delete_image_if_unused(old_image['ImageId'])
      else
        # Image already exists
        # Get matching image
        image_id = matches.first['ImageId']
        # Update user image
        @db.execute("UPDATE User SET ImageId=? WHERE UserId=?", image_id, caller_id)
        # Delete old image if no longer used
        delete_image_if_unused(old_image['ImageId']) unless old_image.nil?
      end
    end

    nil
  end

  # Delete a user
  # @param user_id [Integer] user id to delete
  # @param caller_id [Integer] user id making call
  # @return [nil,String] returns error string on failure
  public def delete_user(user_id, caller_id)

    return $error['BADREQ'] if user_id.nil? || caller_id.nil?

    user = get_user(user_id)
    return $error['NOUSER'] if user.nil?

    caller_user = get_user(caller_id)
    return $error['BADPERM'] unless caller_id == user_id || caller_user["UserPrivilege"] > 0

    image_id = user["ImageId"]

    @db.execute("DELETE FROM User WHERE UserId=?", user_id)

    delete_image_if_unused(image_id)

    nil
  end

  # Create a new board
  # @param board [String] name of board
  # @param caller_id [Integer] user id making call
  # @return [Integer,String] returns id of created board.
  #                          returns error string on failure.
  public def create_board(board, caller_id)

    return $error['BADREQ'] if board.nil? || caller_id.nil?

    board.strip!
    board = Validator.sanitize_name(board)

    return $error['BADNAME'] if board.empty?

    user = get_user(caller_id)

    return $errror['NOUSER'] if user.nil?
    return $error['BADPERM'] unless user["UserPrivilege"] > 0

    return $error['BOARDTAKEN'] unless @db.execute("SELECT BoardId FROM Board WHERE BoardName=?",
                                                   board).empty?

    @db.execute("INSERT INTO Board(BoardName,BoardCreationDate,UserId) VALUES(?,?,?)",
                board, Time.now.to_i, caller_id)

    @db.execute("SELECT BoardId FROM Board WHERE BoardName=?", board).first['BoardId']
  end

  # Delete a board
  # @param board_id [Integer] board id to be removed
  # @param caller_id [Integer] user id making call
  # @return [nil,String] returns error string on failure
  public def delete_board(board_id, caller_id)

    return $error['BADREQ'] if board_id.nil? || caller_id.nil?

    user = get_user(caller_id)
    return $error['NOUSER'] if user.nil?

    board = get_board(board_id)
    return $error['NOBOARD'] if board.nil?

    return $error['BADPERM'] unless user["UserPrivilege"] > 0 ||
      board["UserId"] == user["UserId"]

    @db.execute("DELETE FROM Board WHERE BoardId=?", board_id)

    nil
  end

  # Create a new thread
  # @param thread [String] name of thread
  # @param board_id [Integer] board to post to
  # @param caller_id [Integer] creator of thread
  # @return [Integer,String] returns id of created board.
  #                          returns error string on failure.
  public def create_thread(thread, board_id, caller_id)

    return $error['BADREQ'] if thread.nil? || board_id.nil? || caller_id.nil?

    thread.strip!
    thread = Validator.sanitize_name(thread)

    return $error['BADNAME'] if thread.empty?

    user = get_user(caller_id)
    return $error['NOUSER'] if user.nil?

    board = get_board(board_id)
    return $error['NOBOARD'] if board.nil?

    return $error['TRHEADTAKEN'] unless @db.execute("SELECT ThreadId FROM Thread WHERE ThreadName=?",
                                                   thread).empty?

    @db.execute("INSERT INTO Thread(ThreadName,ThreadCreationDate,ThreadStickied,"\
      "BoardId,UserId) VALUES(?,?,?,?,?)", thread, Time.now.to_i, 0, board_id, caller_id)

    @db.execute("SELECT ThreadId FROM Thread WHERE ThreadName=?", thread).first['ThreadId']
  end

  # Delete a thread
  # @param thread_id [Integer] board to delete
  # @param caller_id [Integer] issuer of call
  # @return [nil,String] returns error string on failure
  public def delete_thread(thread_id, caller_id)

    return $error['BADREQ'] if thread_id.nil? || caller_id.nil?

    user = get_user(caller_id)
    return $error['NOUSER'] if user.nil?

    thread = get_thread(thread_id)
    return $error['NOTHREAD'] if thread.nil?

    return $error['BADPERM'] unless user["UserPrivilege"] > 0 ||
      thread["UserId"] == user["UserId"]

    @db.execute("DELETE FROM Thread WHERE ThreadId=?", thread_id)

    nil
  end

  # Create a new post
  # @param content [String] content of post
  # @param thread_id [Integer] thread to post to
  # @param caller_id [Integer] creator of post
  # @return [nil,String] returns error string on failure
  public def create_post(content, thread_id, caller_id)

    return $error['BADREQ'] if content.nil? || thread_id.nil? || caller_id.nil?

    content.strip!
    content = Validator.sanitize_content(content)

    return $error['BADCONTENT'] if content.empty?

    user = get_user(caller_id)
    return $error['NOUSER'] if user.nil?

    board = get_thread(thread_id)
    return $error['NOTHREAD'] if board.nil?

    time = Time.now.to_i

    @db.execute("INSERT INTO Post(PostContent,PostCreationDate,UserId,ThreadId)"\
      "VALUES(?,?,?,?)", content, time, caller_id, thread_id)


    # Get PostId of new post
    post_id = @db.execute("SELECT PostId FROM Post WHERE PostContent=? AND PostCreationDate=? AND "\
                          "UserId=? AND ThreadId=?", content, time, caller_id, thread_id).first['PostId']

    # Add watching users to unread list
    @db.execute("SELECT UserId FROM UserWatchingThread WHERE ThreadId=?", thread_id).each do |watcher|
      @db.execute("INSERT INTO UserUnreadPost(UserId, PostId) VALUES(?,?)", watcher['UserId'], post_id)
    end

    nil
  end

  # Mark post as unread for mods
  # the first in the thread.
  # @param post_id [Integer] post to report
  # @return [nil]
  public def report(post_id)
    @db.execute("SELECT UserId FROM User WHERE UserPrivilege>0").each do |admin|
      @db.execute("INSERT INTO UserUnreadPost(UserId, PostId) VALUES(?,?)", admin['UserId'], post_id)
    end
  end

  # Delete a post. Deltes thread if the post deleted was
  # the first in the thread.
  # @param post_id [Integer] post to delete
  # @param caller_id [Integer] issuer of call
  # @return [Bool,String] returns true if thread still exists
  #                       and false if it was deleted.
  #                       returns error string on failure.
  public def delete_post(post_id, caller_id)

    return $error['BADREQ'] if post_id.nil? || caller_id.nil?

    user = get_user(caller_id)
    return $error['NOUSER'] if user.nil?

    post = get_post(post_id)
    return $error['NOPOST'] if post.nil?

    return $error['BADPERM'] unless user["UserPrivilege"] > 0 ||
      post["UserId"] == user["UserId"]

    first_post = @db.execute("SELECT * FROM Post WHERE ThreadId=? "\
                             "ORDER BY PostCreationDate ASC", post['ThreadId']).first

    if first_post == post
      @db.execute("DELETE FROM Thread WHERE ThreadId=?", post['ThreadId'])
      return false
    else
      @db.execute("DELETE FROM Post WHERE PostId=?", post_id)
      return true
    end

    nil
  end

  # Sticky or unsticky a thread to a board
  # @param thread_id [Integer] thread to sticky
  # @param sticky    [Bool] if true, thread is sticked, if false thread is unstickied
  # @param caller_id [Integer] issuer of call
  # @return [nil,String] returns error string on failure
  public def update_sticky_thread(thread_id, sticky, caller_id)

    return $error['BADREQ'] if thread_id.nil? || sticky.nil? || caller_id.nil?

    user = get_user(caller_id)
    return $error['NOUSER'] if user.nil?

    thread = @db.execute("SELECT Board.UserId,Thread.ThreadId FROM Thread INNER JOIN Board "\
                         "ON Thread.BoardId = Board.BoardId WHERE ThreadId=?", thread_id)
    return $error['NOTHREAD'] if thread.empty?

    return $error['BADPERM'] unless user["UserPrivilege"] > 0 ||
      thread["UserId"] == user["UserId"] # actually checks board owner, not thread

    @db.execute("UPDATE Thread SET ThreadStickied=? WHERE ThreadId=?", sticky,
                thread_id)

    nil
  end

  # Start watching a thread
  # @param thread_id [Integer] thread to watch
  # @param caller_id [Integer] issuer of call
  # @return [nil,String] returns error string on failure
  public def start_watching(thread_id, caller_id)

    return $error['BADREQ'] if thread_id.nil? || caller_id.nil?

    return $error['NOTHREAD'] if get_thread(thread_id).nil?
    return $error['NOUSER'] if get_user(caller_id).nil?

    # Don't add users already watching again
    if @db.execute("SELECT * FROM UserWatchingThread WHERE ThreadId=? AND UserId=?",
        thread_id, caller_id).empty?
      @db.execute("INSERT INTO UserWatchingThread(ThreadId,UserId) VALUES(?,?)", thread_id, caller_id)
    end

    nil
  end

  # Stop watching a thread
  # @param thread_id [Integer] thread to watch
  # @param caller_id [Integer] issuer of call
  # @return [nil,String] returns error string on failure
  public def stop_watching(thread_id, caller_id)

    return $error['BADREQ'] if thread_id.nil? || caller_id.nil?

    return $error['NOTHREAD'] if get_thread(thread_id).nil?
    return $error['NOUSER'] if get_user(caller_id).nil?
    @db.execute("DELETE FROM UserWatchingThread WHERE ThreadId=? AND UserId=?",
                thread_id, caller_id)

    nil
  end

  # Get a list of unread posts
  # @param caller_id [Integer] issuer of call
  # @return [Array,String] returns array of post ids which are unread.
  #                        returns error string on failure
  public def get_unread(caller_id)

    return [] if caller_id.nil?

    return [] if get_user(caller_id).nil?
    @db.execute("SELECT * FROM UserUnreadPost INNER JOIN Post ON UserUnreadPost.PostId=Post.PostId "\
                "INNER JOIN Thread ON Thread.ThreadId = Post.ThreadId "\
                "INNER JOIN User   ON Thread.UserId   = User.UserId   "\
                "WHERE UserUnreadPost.UserId=?", caller_id)
  end

  # Get a list of watched posts
  # @param caller_id [Integer] issuer of call
  # @return [Array] returns an erroy of watched thread ids on success.
  #                 returns empty array on fail.
  public def get_watched(caller_id)

    return [] if caller_id.nil?
    return [] if get_user(caller_id).nil?

    result = @db.execute("SELECT ThreadId FROM UserWatchingThread WHERE UserId=?", caller_id)
    return [] if result.nil?

    return result.map do |hash|
      hash['ThreadId']
    end
  end

  # Edit a post
  # @param content [String] new content of post
  # @param post_id [Integer] post to edit
  # @param caller_id [Integer] issuer of call
  # @return [nil,String] returns error string on failure
  public def edit_post(content, post_id, caller_id)
    post = get_post(post_id)

    return $error['NOPOST'] if post.nil?
    return $error['BADPERM'] if post['UserId'] != caller_id

    @db.execute("UPDATE Post SET PostContent=? WHERE PostId=?", content, post_id)
  end

  # Mark a thread as unread
  # @param thread_id [Integer] thread to mark as read
  # @param caller_id [Integer] issuer of call
  # @return [nil,String] returns error string on failure
  public def mark_thread_read(thread_id, caller_id)

    return $error['BADREQ'] if thread_id.nil? || caller_id.nil?

    return $error['NOTHREAD'] if get_thread(thread_id).nil?
    return $error['NOUSER'] if get_user(caller_id).nil?
    # My SQLite magnum opus!
    @db.execute("DELETE FROM UserUnreadPost WHERE PostId IN "\
                "(SELECT UserUnreadPost.PostId FROM UserUnreadPost INNER JOIN Post "\
                "ON UserUnreadPost.PostId=Post.PostId WHERE Post.ThreadId=?) AND UserId=?",
                thread_id, caller_id)

    nil
  end

  # Get a list of boards as well as their creator
  # @return [Hash Array] Hash array with all user and board database fields
  public def get_boards
    @db.execute("SELECT * FROM Board INNER JOIN User ON Board.UserId=User.UserId "\
                "INNER JOIN Image WHERE User.ImageId=Image.ImageId "\
                "ORDER BY BoardCreationDate DESC")
  end

  # Get a list of threads as well as their creator from a board
  # @param board_id [Integer] board to get threads from
  # @return [Hash,String] Hash with :board board hash and :threads 
  #                       array with all user, image and thread database fields.
  #                       returns string on error.
  public def get_threads(board_id)

    return $error['BADREQ'] if board_id.nil?

    board = get_board(board_id)
    return $error['NOBOARD'] if board.nil?

    threads = @db.execute("SELECT * FROM Thread INNER JOIN User ON Thread.UserId=User.UserId "\
                "INNER JOIN Image ON Image.ImageId=User.ImageId "\
                "WHERE BoardId=? ORDER BY ThreadStickied DESC, ThreadCreationDate ASC", board_id)

    return { board: board, threads: threads }
  end

  # Get a list of posts as well as their creators from a thread
  # @param thread_id [Integer] thread to get posts from
  # @return [Hash,String] Hash with :thread thread hash :board board hash
  #                       and :posts hash array with all user, image and post
  #                       database fields. returns string on error.
  public def get_posts(thread_id)
    
    return $error['BADREQ'] if thread_id.nil?

    thread = get_thread(thread_id)
    return $error['NOTHREAD'] if thread.nil?

    board = get_board(thread['BoardId'])

    posts = @db.execute("SELECT * FROM User INNER JOIN Post ON Post.UserId=User.UserId "\
                        "INNER JOIN Image ON Image.ImageId=User.ImageId "\
                        "WHERE ThreadId=? ORDER BY PostCreationDate ASC", thread_id)

    return { thread: thread, board: board, posts: posts }
  end

  # Return the user of the given user_id from the database
  # @param user_id [Integer] the user_id of the user to be retrieved
  # @return [Hash,nil] returns user hash with image info if found or nil if not found
  public def get_user(user_id)

    return $error['BADREQ'] if user_id.nil?

    user = @db.execute("SELECT * FROM User WHERE UserId=?", user_id)
    return $error['NOUSER'] if user.empty?
    return user.first
  end

  # Return the image of a given user_id
  # @param user_id [Integer] the user_id who's image should be retrieved
  # @return [Hash,nil] returns user hash with image info if found or nil if not found
  public def get_image(user_id)

    return $error['BADREQ'] if user_id.nil?

    image = @db.execute("SELECT Image.ImageId,ImageMD5,ImageFilepath FROM User INNER JOIN Image ON "\
                       "User.ImageId=Image.ImageId WHERE UserId=?", user_id)

    return $error['NOIMAGE'] if image.empty?
    image.first
  end

  # Return the post of the given post_id from the database
  # @param post_id [Integer] the post id to be retrieved
  # @return [Hash,nil] returns post hash if found or nil if not found
  public def get_post(post_id)
    post = @db.execute("SELECT * FROM Post WHERE PostId=?", post_id)
    return nil if post.empty?
    return post.first
  end

  ########################
  ### DEBUG DEFS BELOW ###
  ########################

  # Set a users privilege level. Only used in debugging.
  # Does not validate input.
  # @param user_id [Integer] user to update
  # @param level [Integer] new privelege level to assign
  # @return [nil]
  public def set_priv(user_id, level)
    @db.execute("UPDATE User SET UserPrivilege=? WHERE UserId=?", level, user_id)
    nil
  end

  ##########################
  ### PRIVATE DEFS BELOW ###
  ##########################

  # Delete an image if no user uses it
  # @param image_id [Integer] image to remove
  private def delete_image_if_unused(image_id)
    return if image_id == 1
    if image_id != nil && @db.execute("SELECT * FROM User WHERE ImageId=?", image_id).empty?
      # Remove image from disk too
      image_path = @db.execute("SELECT ImageFilepath FROM Image WHERE ImageId=?",
                               image_id).first["ImageFilepath"]
      File.delete(image_path) if File.exists? image_path
      @db.execute("DELETE FROM Image WHERE ImageId=?", image_id)
    end
  end

  # Make sure a table exists
  # @param name [String] the name of the table
  # @param members [String] the member declerations
  # @return [nil]
  private def init_table(name, members)
    @db.execute("CREATE TABLE IF NOT EXISTS #{name} (#{members})")
  end

  # Return the board of the given board_id from the database
  # @param board_id [Integer] the board id to be retrieved
  # @return [Hash,nil] returns board hash if found or nil if not found
  private def get_board(board_id)
    board = @db.execute("SELECT * FROM Board WHERE BoardId=?", board_id)
    return nil if board.empty?
    return board.first
  end

  # Return the thread of the given thread_id from the database
  # @param thread_id [Integer] the thread id to be retrieved
  # @return [Hash,nil] returns thread hash if found or nil if not found
  private def get_thread(thread_id)
    thread = @db.execute("SELECT * FROM Thread WHERE ThreadId=?", thread_id)
    return nil if thread.empty?
    return thread.first
  end

end

# Handles validations
class Validator
  # Sanitize a string
  # @param string [String] string to sanitize
  # @param type [Symbol] must either be :name or :content
  # @return [String] sanitized string
  def self.sanitize(string, type)
    Sanitize.fragment(string, $sanitize_opts[type])
  end

  # Sanitize a name
  # @param name [String] string to sanitize
  # @return [String] sanitized string
  def self.sanitize_name(name)
    sanitize(name, :name)
  end

  # Sanitize a content
  # @param content [String] string to sanitize
  # @return [String] sanitized string
  def self.sanitize_content(content)
    sanitize(content, :content)
  end

  # Check if a string is a valid email address
  # @param string [String] string to check
  # @return [TrueClass,FalseClass] boolean success value
  def self.mail?(string)
    # WORD @ WORD . WORD
    return false unless sanitize_name(string) == string
    not string.scan(/^\w+@\w+\.\w+$/).empty?
  end

  # Check if a string is a valid password
  # @param string [String] string to check
  # @return [TrueClass,FalseClass] boolean success value
  def self.password?(string)
    string.length >= 8
  end

  # Check if a string is a valid username
  # @param string [String] string to check
  # @return [TrueClass,FalseClass] boolean success value
  def self.username?(string)
    return false unless sanitize_name(string) == string
    # Username cannot begin with digits and must be 5-32 digits
    not string.scan(/^\D\w{4,31}$/).empty?
  end

  @@attempt_hash = {}
  # Check if a login should time out
  # @param identifier [String] IP address of login attempt
  # @return [TrueClass,FalseClass] true if login is allowed
  def self.timeout? identifier
    @@attempt_hash[identifier] = [] if @@attempt_hash[identifier].nil?
    time = Time.now


    # Clear all outdated entries
    @@attempt_hash.keys.each do |key|
      @@attempt_hash[key].select! do |timestamp|
        time - timestamp < 10
      end
    end
    @@attempt_hash[identifier] << time

    return false if @@attempt_hash[identifier].length >= 4
    return true
  end
end
