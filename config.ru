require 'rubygems'
require 'bundler/setup'

Bundler.require

require './web'
run Sinatra::Application
