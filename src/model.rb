require 'sqlite3'
require 'bcrypt'
require 'sanitize'

require_relative 'view.rb'

# Exit program printing an error message
# @param msg [String] message to print before exit
def die(msg)
  STDERR.puts(msg)
  exit 1
end

# NOTE:
# Use join to sort boards by latest posted post in thread.
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
class DataBase
  # Create a new DataBase connection
  # @param path [String] the path to the database file
  # @return [DataBase]
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
      "ImageId INTEGER,"\
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
  end

  # Authenticate a user login
  # @param user [String] the username
  # @param pass [String] the password
  # @param identifier [String] identifier used to stop spam
  #   attempts, (probably the IP address)
  # @return [Integer,String] on sucess returns user id, otherwise
  #   returns error string.
  public def log_in(user, pass, identifier)

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
  # TODO
  # - more verbose/informative messages to help with
  #   formatting
  # @param user [String] the username
  # @param pass [String] the password
  # @param identifier [String] identifier used to stop spam
  #   attempts, (probably the IP address)
  # @return [Integer,String] on sucess returns user id, otherwise
  #   returns error string.
  public def register(user, pass, repeat_pass, identifier)

    user.strip!
    pass.strip!
    repeat_pass.strip!
    
    return $error['TIMEOUT'] unless Validator.timeout? identifier
    return $error['NOMATCH'] unless pass == repeat_pass
    return $error['BADUSER'] unless Validator.username? user
    return $error['BASPASS'] unless Validator.password? pass

    result = @db.execute("SELECT * FROM User WHERE UserName=?", user)
    return $error['USERTAKEN'] unless result.empty?

    pass_digest = BCrypt::Password.create(pass)
    @db.execute("INSERT INTO User(UserName, UserFooter, UserPrivilege, UserRegistrationDate)"\
      "VALUES(?,?,?,?)", user, "I'm new here!", 0, Time.now.to_i)

    id = @db.execute("SELECT UserId FROM User WHERE UserName=?", user).first["UserId"]

    @db.execute("INSERT INTO Hash(Hash, UserId) VALUES(?,?)", pass_digest, id)

    return id

  end

  # Update user settings. Any argument set to nil or an
  # empty string will not be updated.
  # @param caller_id [Integer] issuer of call
  # @param user_name [String] new name
  # @param user_footer [String] new footer
  # @return [nil,String] returns error string on failure
  public def update_user(caller_id, user_name, user_footer)

    user_name.strip!
    user_footer.strip!

    return $error['BADUSER'] unless Validator.username? user_name

    user = get_user(caller_id)
    return $error['NOUSER'] if user == nil

    updates = []
    unless user_name.nil? || user_name.empty?
      return $error['USERTAKEN'] unless @db.execute("SELECT * FROM User WHERE UserName=?",
                                                    user_name).empty?
      updates << { key: "UserName", value: user_name }
    end
    unless user_footer.nil? || user_footer.empty?
      user_footer = Validator.sanitize_content(user_footer)
      return $error['BADCONTENT'] if user_footer.empty?

      updates << { key: "UserFooter", value: user_footer }
    end

    updates.each do |u|
      @db.execute("UPDATE User SET #{u[:key]}=? WHERE UserId=?", u[:value], caller_id)
    end

    nil
  end

  # Delete a user
  # @param user_id [Integer] user id to delete
  # @param caller_id [Integer] user id making call
  # @return [nil,String] returns error string on failure
  public def delete_user(user_id, caller_id)

    user = get_user(user_id)
    return $error['NOUSER'] if user == nil

    caller_user = get_user(caller_id)
    return $error['BADPERM'] unless caller_id == user_id || caller_user["UserPrivilege"] > 0

    image_id = user["ImageId"]

    @db.execute("DELETE FROM User WHERE UserId=?", user_id)

    # If no one else uses this image, then remove it
    if image_id != nil && @db.execute("SELECT * FROM User WHERE ImageId=?", image_id).empty?
      # Remove image from disk too
      image_path = @db.execute("SELECT ImageFilepath FROM Image WHERE ImageId=?",
                               image_id).first["ImageFilepath"]
      File.delete(image_path) if File.exists? image_path
      @db.execute("DELETE FROM Image WHERE ImageId=?", image_id)
    end

    nil
  end

  # Create a new board
  # @param board [String] name of board
  # @param caller_id [Integer] user id making call
  # @return [nil,String] returns error string on failure
  public def create_board(board, caller_id)

    board.strip!
    board = Validator.sanitize_name(board)

    return $error['BADNAME'] if board.empty?

    user = get_user(caller_id)

    return $errror['NOUSER'] if user == nil
    return $error['BADPERM'] unless user["UserPrivilege"] > 0

    return $error['BOARDTAKEN'] unless @db.execute("SELECT BoardId FROM Board WHERE BoardName=?",
                                                   board).empty?

    @db.execute("INSERT INTO Board(BoardName,BoardCreationDate,UserId) VALUES(?,?,?)",
                board, Time.now.to_i, caller_id)

    nil
  end

  # Delete a board
  # @param board_id [Integer] board id to be removed
  # @param caller_id [Integer] user id making call
  # @return [nil,String] returns error string on failure
  public def delete_board(board_id, caller_id)
    user = get_user(caller_id)
    return $error['NOUSER'] if user == nil

    board = get_board(board_id)
    return $error['NOBOARD'] if board == nil

    return $error['BADPERM'] unless user["UserPrivilege"] > 0 ||
      board["UserId"] == user["UserId"]

    @db.execute("DELETE FROM Board WHERE BoardId=?", board_id)

    nil
  end

  # Create a new thread
  # @param thread [String] name of thread
  # @param board_id [Integer] board to post to
  # @param caller_id [Integer] creator of thread
  # @return [nil,String] returns error string on failure
  public def create_thread(thread, board_id, caller_id)

    thread.strip!
    thread = Validator.sanitize_name(strip)

    return $error['BADNAME'] if thread.empty?

    user = get_user(caller_id)
    return $error['NOUSER'] if user == nil

    board = get_board(board_id)
    return $error['NOBOARD'] if board == nil

    @db.execute("INSERT INTO Thread(ThreadName,ThreadCreationDate,ThreadStickied,"\
      "BoardId,UserId) VALUES(?,?,?,?,?)", thread, Time.now.to_i, 0, board_id, caller_id)

    nil
  end

  # Delete a thread
  # @param thread_id [Integer] board to delete
  # @param caller_id [Integer] issuer of call
  # @return [nil,String] returns error string on failure
  public def delete_thread(thread_id, caller_id)
    user = get_user(caller_id)
    return $error['NOUSER'] if user == nil

    thread = get_thread(thread_id)
    return $error['NOTHREAD'] if board == nil

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

    content = content.strip!
    content = Validator.sanitize_content(content)

    return $error['BADCONTENT'] if content.empty?

    user = get_user(caller_id)
    return $error['NOUSER'] if user == nil

    board = get_thread(thread_id)
    return $error['NOTHREAD'] if board == nil

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

  # Delete a post
  # @param post_id [Integer] post to delete
  # @param caller_id [Integer] issuer of call
  # @return [nil,String] returns error string on failure
  public def delete_post(post_id, caller_id)
    user = get_user(caller_id)
    return $error['NOUSER'] if user == nil

    post = get_post(post_id)
    return $error['NOPOST'] if post == nil

    return $error['BADPERM'] unless user["UserPrivilege"] > 0 ||
      post["UserId"] == user["UserId"]

    @db.execute("DELETE FROM Post WHERE PostId=?", post_id)

    nil
  end

  # Sticky or unsticky a thread to a board
  # @param thread_id [Integer] thread to sticky
  # @param caller_id [Integer] issuer of call
  # @param sticky    [Bool] if true, thread is sticked, if false thread is unstickied
  # @return [nil,String] returns error string on failure
  public def update_sticky_thread(thread_id, caller_id, sticky)
    user = get_user(caller_id)
    return $error['NOUSER'] if user == nil

    thread = @db.execute("SELECT Board.UserId,Thread.ThreadId FROM Thread INNER JOIN Board "\
                         "ON Thread.BoardId = Board.BoardId WHERE ThreadId=?", thread_id)
    return $error['NOTHREAD'] if thread.empty?

    return $error['BADPERM'] unless user["UserPrivilege"] > 0 ||
      thread["UserId"] == user["UserId"] # actually checks board owner, not thread

    @db.execute("UPDATE Thread SET ThreadStickied=? WHERE ThreadId=?", sticky ? 1 : 0,
                thread_id)

    nil
  end

  # Start watching a thread
  # @param thread_id [Integer] thread to watch
  # @param caller_id [Integer] issuer of call
  # @return [nil,String] returns error string on failure
  public def start_watching(thread_id, caller_id)
    return $error['NOTHREAD'] if get_thread(thread_id) == nil
    return $error['NOUSER'] if get_user(caller_id) == nil

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
    return $error['NOTHREAD'] if get_thread(thread_id) == nil
    return $error['NOUSER'] if get_user(caller_id) == nil
    @db.execute("DELETE FROM UserWatchingThread WHERE ThreadId=? AND UserId=?",
                thread_id, caller_id)

    nil
  end

  # Get a list of unread posts
  # @param caller_id [Integer] issuer of call
  # @return [nil,String] returns error string on failure
  public def get_unread(caller_id)
    return $error['NOUSER'] if get_user(caller_id) == nil
    @db.execute("SELECT * FROM UserUnreadPost INNER JOIN Post ON UserUnreadPost.PostId=Post.PostId "\
                "WHERE UserUnreadPost.UserId=?", caller_id)

    nil
  end

  # Mark a thread as unread
  # @param thread_id [Integer] thread to mark as read
  # @param caller_id [Integer] issuer of call
  # @return [nil,String] returns error string on failure
  public def mark_thread_read(thread_id, caller_id)
    return $error['NOTHREAD'] if get_thread(thread_id) == nil
    return $error['NOUSER'] if get_user(caller_id) == nil
    # My SQLite magnum opus!
    @db.execute("DELETE FROM UserUnreadPost WHERE PostId IN "\
                "(SELECT UserUnreadPost.PostId FROM UserUnreadPost INNER JOIN Post "\
                "ON UserUnreadPost.PostId=Post.PostId WHERE Post.ThreadId=?)", thread_id)

    nil
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
  end

  ##########################
  ### PRIVATE DEFS BELOW ###
  ##########################

  # Make sure a table exists
  # @param name [String] the name of the table
  # @param members [String] the member declerations
  # @return [nil]
  private def init_table(name, members)
    @db.execute("CREATE TABLE IF NOT EXISTS #{name} (#{members})")
  end

  # Return the user of the given user_id from the database
  # @param user_id [Integer] the user_id of the user to be retrieved
  # @return [Hash,nil] returns user hash if found or nil if not found
  private def get_user(user_id)
    user = @db.execute("SELECT * FROM User WHERE UserId=?", user_id)
    return nil if user.empty?
    return user.first
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

  # Return the post of the given post_id from the database
  # @param post_id [Integer] the post id to be retrieved
  # @return [Hash,nil] returns post hash if found or nil if not found
  private def get_post(post_id)
    post = @db.execute("SELECT * FROM Post WHERE PostId=?", post_id)
    return nil if post.empty?
    return post.first
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
    string.length > 8
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
    @@attempt_hash[identifier] = [] if @@attempt_hash[identifier] == nil
    time = Time.now


    # Clear all outdated entries
    @@attempt_hash.each do |key|
      next if @@attempt_hash[key] == nil
      @@attempt_hash[key].select! do |timestamp|
        time - timestamp < 10
      end
    end
    @@attempt_hash[identifier] << time

    return false if @@attempt_hash[identifier].length >= 4
    return true
  end
end
