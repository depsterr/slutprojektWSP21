# The default document title
$sitename = 'forum.rb'
# Hash of error strings
$error = {
  'NOMATCH'     => "Passwords do not match",
  'WRONGPASS'   => "Invalid Password",
  'BADPASS'     => "Invalid Password",
  'BADUSER'     => "Invalid Username",
  'BADNAME'     => "Invalid name",
  'BADCONTENT'  => "Invalid content",
  'NOUSER'      => "User does not exist",
  'NOBOARD'     => "Board does not exist",
  'NOTHREAD'    => "Thread does not exist",
  'NOPOST'      => "Post does not exist",
  'USERTAKEN'   => "Username already taken",
  'BOARDTAKEN'  => "A board with this name already exists",
  'THREADTAKEN' => "A thread with this name already exists",
  'TIMEOUT'     => "You're doing this too much. Please try again later",
  'BADPERM'     => "You're not allowed to do that",
}
# Sanitizing options for different types of data
$sanitize_opts = {
  # Name of users and threads
  name: {},
  # Post contents and user footers
  content: {
    elements: ['b', 'i', 'a', 'ul', 'ol', 'li', 'table', 'tr', 'th', 'td', 'img'],
    attributes: {
      'a' => ['href'],
      'img' => ['href', 'src', 'alt']
    }
  }
}
