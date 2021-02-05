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
    @db = Sqlite3::open path
    @db.results_as_hash = true

    # Setup tables (move this out of here if we need to
    # rerun this for each route).
    # tables
    init_table "Hash" "HashId INTEGER PRIMARY KEY AUTOINCREMENT,"\
      "Hash STRING NOT NULL"\
      "FOREIGN KEY(UserId) REFERENCES User(UserId)"

    init_table "Image" "ImageId INTEGER PRIMARY KEY AUTOINCREMENT,"\
      "ImageMD5 STRING NOT NULL,"\
      "ImageFilepath STRING NOT NULL"

    init_table "User" "UserId INTEGER PRIMARY KEY AUTOINCREMENT,"\
      "UserName STRING NOT NULL,"\
      "UserFooter STRING NOT NULL,"\
      "UserPrivilege INTEGER NOT NULL,"\
      "UserRegistrationDate INTEGER NOT NULL"

    init_table "Post" "PostId INTEGER PRIMARY KEY AUTOINCREMENT,"\
      "PostContent STRING NOT NULL,"\
      "PostCreationDate INTEGER NOT NULL"\
      "FOREIGN KEY(UserId) REFERENCES User(UserId)"\
      "FOREIGN KEY(ThreadId) REFERENCES Thread(ThreadId)"

    init_table "Thread" "ThreadId INTEGER PRIMARY KEY AUTOINCREMENT,"\
      "ThreadName STRING NOT NULL,"\
      "ThreadCreationDate INTEGER NOT NULL"\
      "ThreadStickied INTEGER NOT NULL"\
      "FOREIGN KEY(BoardId) REFERENCES Board(BoardId)"\
      "FOREIGN KEY(UserId) REFERENCES User(UserId)"

    init_table "Board" "BoardId INTEGER PRIMARY KEY AUTOINCREMENT,"\
      "BoardName STRING NOT NULL,"\
      "BoardCreationDate INTEGER NOT NULL"\
      "FOREIGN KEY(UserId) REFERENCES User(UserId)"

    # relation tables
    init_table "UserImageRelation" "FOREIGN KEY(UserID) REFERENCES User(UserID)"\
      "FOREIGN KEY(ImageId) REFERENCES Image(ImageId)"

    init_table "UserUnreadPost" "FOREIGN KEY(UserID) REFERENCES User(UserID)"\
      "FOREIGN KEY(PostId) REFERENCES Post(PostId)"

    init_table "UserUnreadThread" "FOREIGN KEY(UserID) REFERENCES User(UserID)"\
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
    @db.exec "CREATE TABLE IF NOT EXISTS #{name} (#{members})"
  end
end
