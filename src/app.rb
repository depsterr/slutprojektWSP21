#!/usr/bin/env ruby

require 'sinatra'
require 'slim'
require 'slim/include' # enable "include" in templates
require 'bcrypt'

require_relative 'database.rb'
require_relative 'validate.rb'

$SITENAME = "forum.rb"

helpers do
  # @return [String] the name of the current page
  def page_name
    if defined? docname
      docname
    else
      $SITENAME
    end
  end
end

Dir.mkdir 'db' unless Dir.exists? 'db'
db = DataBase.new "db/database.sqlite"

get '/' do
  slim :index
end
