require 'sqlite3'
require 'bcrypt'

require_relative 'view.rb'

# This class is used to abstract away database operations.
# Dates are stored as integers using unix epoch.
# Booleans are stored as 1/0 integers.
# User privelege levels:
#  - 0: normal (logged in) user
#  - 1: admin
# TODO:
#  - Log in
#  - Register
#  - Delete User
#  - Create/Delete Board
#  - Create/Delete Thread
#  - Create/Delete Post
#  - Watch Post
#  - Edit user settings
class DataBase
  # Create a new DataBase connection
  # @param path [String] the path to the database file
  # @return [DataBase]
  public def initialize(path)
    raise TypeError if path.class != String
    @db = SQLite3::Database.new path
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
    init_table("UserWatchingPost", "UserId INTEGER NOT NULL,"\
      "PostId INTEGER NOT NULL,"\
      "FOREIGN KEY(UserId) REFERENCES User(UserId) ON DELETE CASCADE,"\
      "FOREIGN KEY(PostId) REFERENCES Post(PostId) ON DELETE CASCADE")

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

  # Delete a user
  # @param caller_id [Integer] user id making call
  # @param user_id [Integer] user id to delete
  # @return [nil]
  public def delete_user(caller_id, user_id)

    user = @db.execute("SELECT * FROM User WHERE UserId=?", user_id).first
    caller_user = @db.execute("SELECT * FROM User WHERE UserId=?", caller_id).first

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

  end

  # Create a new board
  # @param board [String] name of board
  # @param caller_id [Integer] user id making call
  public def create_board(board, caller_id)
  end

  # Make sure a table exists
  # @param name [String] the name of the table
  # @param members [String] the member declerations
  private def init_table name, members
    @db.execute("CREATE TABLE IF NOT EXISTS #{name} (#{members})")
  end
end

# Handles validations
class Validator
  # Check if a string is a valid email address
  # @param string [String] string to check
  # @return [TrueClass,FalseClass] boolean success value
  def self.mail?(string)
    # WORD @ WORD . WORD
    not string.scan(/^\w+@\w+\.\w+$/).empty?
  end

  # Check if a string is a valid password
  # @param string [String] string to check
  # @return [TrueClass,FalseClass] boolean success value
  def self.password?(string)
    # TODO password formatting
    true
  end

  # Check if a string is a valid username
  # @param string [String] string to check
  # @return [TrueClass,FalseClass] boolean success value
  def self.username?(string)
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
    @@attempt_hash[identifier].select! do |timestamp|
      time - timestamp < 10
    end
    @@attempt_hash[identifier] << time

    return false if @@attempt_hash[identifier].length >= 4
    return true
  end
end
