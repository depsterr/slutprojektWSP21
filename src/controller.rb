#!/usr/bin/env ruby

require 'sinatra'
require 'slim'
require 'slim/include' # enable "include" in templates

require_relative 'model.rb'
require_relative 'view.rb'

# TODO:
#  - [x] finish model.rb TODOs
#  - [ ] Home/Boards page
#  - [ ] Board/Threads page
#  - [ ] Thread/Posts page
#  - [ ] Error page
#  - [ ] REST routes för att interagera med DataBase klassen
#        (skulle kunna använda en lookup table approach?)
#  - [ ] Register page
#  - [ ] Log in page
#  - [ ] User profile page
#  - [ ] User options

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
end

get '/' do
  slim :index
end
