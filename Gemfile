source "https://rubygems.org"

gem "sinatra"

# The rerun command restarts the app if your files change
gem "rerun"
gem 'rb-fsevent', '~> 0.9.1'
gem 'sinatra-contrib'
gem 'data_mapper'
gem 'sinatra-flash'
gem 'haml'
gem 'sinatra-authentication'
gem 'dm-core'
gem 'dm-validations'


group :production do
  gem 'pg'
  gem 'thin'
end        

group :development do
  gem 'sqlite3'
  gem 'dm-sqlite-adapter'
end
