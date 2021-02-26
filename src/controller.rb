#!/usr/bin/env ruby

require 'sinatra'
require 'slim'
require 'slim/include' # enable "include" in templates

require_relative 'model.rb'
require_relative 'view.rb'

helpers do
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
