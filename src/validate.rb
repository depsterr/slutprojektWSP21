# Handles validations
class Validator
  # Check if a string is a valid email address
  # @param string [String] string to check
  # @return [TrueClass,FalseClass] boolean success value
  def self.mail? string
    # WORD @ WORD . WORD
    not string.scan(/^\w+@\w+\.\w+$/).empty?
  end

  # Check if a string is a valid password
  # @param string [String] string to check
  # @return [TrueClass,FalseClass] boolean success value
  def self.password? string
    # TODO password formatting
    true
  end

  # Check if a string is a valid username
  # @param string [String] string to check
  # @return [TrueClass,FalseClass] boolean success value
  def self.username? string
    # Username cannot begin with digits and must be 5-32 digits
    not string.scan(/^\D\w{4,31}$/).empty?
  end

  @@attempt_hash
  # Check if a login should time out
  # @param identifier [String] IP address of login attempt
  # @return [TrueClass,FalseClass] true if login is allowed
  def self.timeout? identifier
    @@attempt_hash[identifier] = [] if not defined? @@attempt_hash[identifier]
    time = Time.now
    @@attempt_hash[identifier].select! do |timestamp|
      time - timestamp < 10
    end
    @@attempt_hash[identifier] << time

    return false if @@attempt_hash[identifier].length >= 4
    return true
  end
end
