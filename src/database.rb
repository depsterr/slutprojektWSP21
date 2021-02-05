require 'sqlite3'

# This class is used to abstract away database operations.
# Dates are stored as integers using unix epoch.
# Booleans are stored as 1/0 integers.
class DataBase
  # Create a new DataBase connection
  # @param path [String] the path to the database file
  # @return [DataBase]
  public def initialize path 
    raise TypeError if path.class != String
    @db = SQLite3::Database.new path
    @db.results_as_hash = true

    # Setup tables (move this out of here if we need to
    # rerun this for each route).
    # tables
    init_table "User", "UserId INTEGER PRIMARY KEY AUTOINCREMENT,"\
      "UserName STRING NOT NULL,"\
      "UserFooter STRING NOT NULL,"\
      "UserPrivilege INTEGER NOT NULL,"\
      "UserRegistrationDate INTEGER NOT NULL"

    init_table "Hash", "HashId INTEGER PRIMARY KEY AUTOINCREMENT,"\
      "Hash STRING NOT NULL,"\
      "UserId INTEGER NOT NULL,"\
      "FOREIGN KEY(UserId) REFERENCES User(UserId)"

    init_table "Image", "ImageId INTEGER PRIMARY KEY AUTOINCREMENT,"\
      "ImageMD5 STRING NOT NULL,"\
      "ImageFilepath STRING NOT NULL"

    init_table "Board", "BoardId INTEGER PRIMARY KEY AUTOINCREMENT,"\
      "BoardName STRING NOT NULL,"\
      "BoardCreationDate INTEGER NOT NULL,"\
      "UserId INTEGER NOT NULL,"\
      "FOREIGN KEY(UserId) REFERENCES User(UserId)"

    init_table "Thread", "ThreadId INTEGER PRIMARY KEY AUTOINCREMENT,"\
      "ThreadName STRING NOT NULL,"\
      "ThreadCreationDate INTEGER NOT NULL,"\
      "ThreadStickied INTEGER NOT NULL,"\
      "BoardId INTEGER NOT NULL,"\
      "UserId INTEGER NOT NULL,"\
      "FOREIGN KEY(UserId) REFERENCES User(UserId),"\
      "FOREIGN KEY(BoardId) REFERENCES Board(BoardId)"

    init_table "Post", "PostId INTEGER PRIMARY KEY AUTOINCREMENT,"\
      "PostContent STRING NOT NULL,"\
      "PostCreationDate INTEGER NOT NULL,"\
      "UserId INTEGER NOT NULL,"\
      "ThreadId INTEGER NOT NULL,"\
      "FOREIGN KEY(UserId) REFERENCES User(UserId),"\
      "FOREIGN KEY(ThreadId) REFERENCES Thread(ThreadId)"

    # relation tables
    init_table "UserImageRelation", "UserId INTEGER NOT NULL,"\
      "ImageId INTEGER NOT NULL,"\
      "FOREIGN KEY(UserId) REFERENCES User(UserId),"\
      "FOREIGN KEY(ImageId) REFERENCES Image(ImageId)"

    init_table "UserUnreadPost", "UserId INTEGER NOT NULL,"\
      "PostId INTEGER NOT NULL,"\
      "FOREIGN KEY(UserId) REFERENCES User(UserId),"\
      "FOREIGN KEY(PostId) REFERENCES Post(PostId)"

    init_table "UserUnreadThread", "UserId INTEGER NOT NULL,"\
      "ThreadId INTEGER NOT NULL,"\
      "FOREIGN KEY(UserId) REFERENCES User(UserId),"\
      "FOREIGN KEY(ThreadId) REFERENCES Thread(ThreadId)"
  end

  # Authenticate a user login
  # @param user [String] the username
  # @param pass [String] the password
  # @return [Integer] user id
  public def authenticate user, pass
    # TODO add things
    return 1
  end

  # Make sure a table exists
  # @param name [String] the name of the table
  # @param members [String] the member declerations
  private def init_table name, members
    @db.execute "CREATE TABLE IF NOT EXISTS #{name} (#{members})"
  end
end
