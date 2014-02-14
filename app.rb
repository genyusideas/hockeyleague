require 'bundler/setup'
require 'rubygems'
require 'sinatra'
require 'sinatra/contrib/all'
require 'data_mapper'
require 'dm-core'
require 'dm-validations'
require 'sinatra/flash'
require 'Haml'
require "sinatra-authentication"

use Rack::Session::Cookie, :secret => 'TH!S is A S3cRet Key Store F0R H)CK7y Mana%er'

set :sinatra_authentication_view_path, Pathname(__FILE__).dirname.expand_path + "views/auth/"

DataMapper::setup(:default, "sqlite3://#{Dir.pwd}/hockey.db")  
  
class Player  
  include DataMapper::Resource  
  property :id, Serial  
  property :first_name, Text 
  property :last_name, Text  
  property :created_at, DateTime  
  property :updated_at, DateTime  
  
  belongs_to :team
end  

class Team
  include DataMapper::Resource  
  property :id, Serial  
  property :name, Text,:required => true 
  property :created_at, DateTime  
  property :updated_at, DateTime 
  
  has n, :players
end

class Location
  include DataMapper::Resource  
  property :id, Serial  
  property :name, Text   
  property :created_at, DateTime  
  property :updated_at, DateTime 
end

class Game
  include DataMapper::Resource  
  property :id, Serial  
  property :game_date, Date
  property :game_time, String
  property :created_at, DateTime  
  property :updated_at, DateTime 

  belongs_to :location
  belongs_to :home_team, :model => Team
  belongs_to :away_team, :model => Team
  
  validates_with_method :home_team_away_team_cannot_match
  
  def home_team_away_team_cannot_match
    if home_team != away_team 
      return true
    else      
     [ false, "Home Team and Away Team must be different" ]
    end  
  end
end

class League
  include DataMapper::Resource  
  property :id, Serial  
  property :name, Text   
  property :created_at, DateTime  
  property :updated_at, DateTime 
  
  has n, :dm_users, :through => Resource
end

class DmUser    
  has n, :leagues, :through => Resource
end

class Goal
  include DataMapper::Resource  
  property :id, Serial 
  property :period_of_goal, Integer
  property :time_of_goal, String  
  property :created_at, DateTime  
  property :updated_at, DateTime 
  
  belongs_to :goal_scorer, :model => Player
  belongs_to :assist1_player, :model => Player, :required => false
  belongs_to :assist2_player, :model => Player, :required => false
  belongs_to :team
  belongs_to :game
  validates_with_method :one_player_per_goal
  
  def one_player_per_goal
    point = [goal_scorer, assist1_player, assist2_player].compact
    if point.uniq.length == point.length
      return true
    else      
     duplicate = point.detect{ |e| point.count(e) > 1 }
     [ false,  "You selected the following player more then once:   " + duplicate.first_name.upcase + " " +  duplicate.last_name.upcase  ]
    end  
  end
  
end

class Penality
  include DataMapper::Resource  
  property :id, Serial 
  property :period_of_penality, Integer
  property :time_of_penality, String  
  property :penality_type, String
  property :penality_length, Integer
  property :created_at, DateTime  
  property :updated_at, DateTime 
  
  belongs_to :player
  belongs_to :team
  belongs_to :game
end

class GamePlayed
  include DataMapper::Resource  
  property :id, Serial 
  property :created_at, DateTime  
  property :updated_at, DateTime 
  
  belongs_to :roster_player, :model => Player
  belongs_to :team
  belongs_to :game
end

DataMapper.finalize.auto_upgrade! 


configure do
  set :public_folder, Proc.new { File.join(root, "static") }
  enable :sessions
end

helpers do

  def partial(template,locals=nil)
    locals = locals.is_a?(Hash) ? locals : {template.to_sym =>         locals}
    template=('_' + template.to_s).to_sym
    haml(template,{:layout => false},locals)      
  end 

  def username
    session[:identity] ? session[:identity] : 'Hello stranger'
  end
  
  def player_game_stats(player_id, game_id)
    points = Goal.all(:goal_scorer_id => player_id, :game_id => game_id) + Goal.all(:assist1_player_id => player_id, :game_id => game_id) + Goal.all(:assist2_player_id => player_id, :game_id => game_id)
    goals = points.count(:goal_scorer_id => player_id, :game_id => game_id)
    assists = points.count(:assist1_player_id => player_id, :game_id => game_id) + points.count(:assist2_player_id => player_id, :game_id => game_id)
    penalities = Penality.sum(:penality_length, :conditions => [ 'player_id = ? AND game_id = ?', player_id, game_id])
    if penalities.nil?
      penalities = 0
    end
    points = goals + assists
    playerstats = {"Goals" => goals, "Assists" => assists, "Points" => points, "Penalities" => penalities}
  end
  
  def player_stats(player_id)
    points = Goal.all(:goal_scorer_id => player_id) + Goal.all(:assist1_player_id => player_id) + Goal.all(:assist2_player_id => player_id)
    goals = points.count(:goal_scorer_id => player_id)
    assists = points.count(:assist1_player_id => player_id) + points.count(:assist2_player_id => player_id)
    penalities = Penality.sum(:penality_length, :conditions => [ 'player_id = ? ', player_id])
    if penalities.nil?
      penalities = 0
    end
    points = goals + assists
    playerstats = {"Goals" => goals, "Assists" => assists, "Points" => points, "Penalities" => penalities}
  end
 
  def team_game_stats(team_id)
    games = @games.all(:home_team_id => team_id) + @games.all(:away_team_id => team_id)
    wins = loses = ties = goals_for = goals_against = 0
    games.each do |g|
      goals_for_game = @goals.count(:team_id => team_id, :game_id => g.id)
      goals_against_game = @goals.count(:game_id => g.id) - @goals.count(:team_id => team_id, :game_id => g.id)
      if  goals_for_game > goals_against_game
        wins = wins + 1
      elsif goals_against_game > goals_for_game
          loses = loses + 1
      else
        ties = ties + 1      
      end
      goals_for = goals_for + goals_for_game
      goals_against = goals_against + goals_against_game
    end
    games = { "Wins" => wins, "Loses" => loses, "Ties" => ties, "GF" => goals_for, "GA" => goals_against, "GP" => games.count }
  end
  
  def game_played_in(team_id, game_id)
    roster = GamePlayed.all(:game_id => game_id, :team_id => team_id)
  end
  
end



get '/' do
  redirect '/stats'  
end



#*************************
#Player
#*************************
get '/player' do
  @players = Player.all
  @teams = Team.all
  @title = 'All Players'
  haml :player_form
end

post '/player' do  
  p = Player.new  
  p.first_name = params[:first_name]  
  p.last_name = params[:last_name]
  p.team_id = params[:team_id]
  p.created_at = Time.now  
  p.updated_at = Time.now  
  if p.save  
    redirect '/team/'+params[:team_id]
  else
    flash[:error] = p.errors.full_messages  
  end
  redirect '/team/'+params[:team_id]
end  

get '/player/:id' do  
  @player = Player.get params[:id]  
  @teams = Team.all
  @title = "Edit Player ##{params[:id]}"  
  haml :player_edit  
end  

put '/player/:id' do  
  p = Player.get params[:id]  
  p.first_name = params[:first_name]  
  p.last_name = params[:last_name]  
  p.team_id = params[:team_id]  
  p.updated_at = Time.now  
  p.save  
  redirect '/player'  
end  

get '/player/:id/delete' do
  @player = Player.get params[:id]  
  haml :player_delete
end

post '/delete/:id/?' do
  if params.has_key?("ok")
    player = Player.first(:id => params[:id])
    player.destroy
    redirect '/player'
  else
    redirect '/player'
  end
end

#*************************
#Team
#*************************
get '/team' do
  @teams = Team.all
  @title = 'All Teams'
  haml :team_form
end

post '/team' do  
  t = Team.new  
  t.name = params[:name] 
  t.created_at = Time.now  
  t.updated_at = Time.now  
  t.save 
  if t.save  
    redirect '/team'  
  else
    flash[:error] = t.errors.full_messages
	redirect '/team' 
  end
end  

get '/team/:id' do  
  @team = Team.get params[:id]  
  @title = "Edit Team ##{params[:id]}"  
  haml :team_edit  
end  

put '/team/:id' do  
  t = Team.get params[:id]  
  t.name = params[:name] 
  t.updated_at = Time.now  
  t.save  
  redirect '/team'  
end  

get '/team/:id/delete' do
  @team = Team.get params[:id]  
  haml :team_delete
end

post '/team/:id/delete' do
  if params.has_key?("ok")
    team = Team.first(:id => params[:id])
    team.destroy
    redirect '/team'
  else
    redirect '/team'
  end
end

#*************************
#Location
#*************************
get '/location' do
  @locations = Location.all
  @title = 'All Locations'
  haml :location_form
end

post '/location' do  
  t = Location.new  
  t.name = params[:name] 
  t.created_at = Time.now  
  t.updated_at = Time.now  
  t.save  
  redirect '/location'  
end  

get '/location/:id' do  
  @location = Location.get params[:id]  
  @title = "Edit Location ##{params[:id]}"  
  haml :location_edit  
end  

put '/location/:id' do  
  t = Location.get params[:id]  
  t.name = params[:name] 
  t.updated_at = Time.now  
  t.save  
  redirect '/location'  
end  

get '/location/:id/delete' do
  @location = Location.get params[:id]  
  haml :location_delete
end

post '/location/:id/delete' do
  if params.has_key?("ok")
    location = Location.first(:id => params[:id])
    location.destroy
    redirect '/location'
  else
    redirect '/location'
  end
end

#*************************
#Game
#*************************
get '/game' do
  @games = Game.all
  @teams = Team.all
  @locations = Location.all
  @title = 'All Games'
  haml :game_form
end

post '/game' do  
  g = Game.new  
  g.home_team_id = params[:home_team_id]
  g.away_team_id = params[:away_team_id]
  g.location_id = params[:location_id]
  g.game_date = params[:game_date]
  g.game_time = params[:game_time]
  g.created_at = Time.now  
  g.updated_at = Time.now  
  if g.save  
    redirect '/game'  
  else
    flash[:error] = g.errors.full_messages
	redirect '/game' 
  end  
end  

get '/game/:id' do  
  @game = Game.get params[:id]  
  @teams = Team.all
  @locations = Location.all
  @title = "Edit Game ##{params[:id]}"  
  haml :game_edit  
end  

put '/game/:id' do  
  g = Game.get params[:id]  
  g.home_team_id = params[:home_team_id]
  g.away_team_id = params[:away_team_id]
  g.location_id = params[:location_id]
  g.game_date = params[:game_date]
  g.game_time = params[:game_time]
  g.updated_at = Time.now  
  if g.save  
    redirect '/game'  
  else
    flash[:error] = g.errors.full_messages
	redirect '/game' 
  end  
end  

get '/game/:id/delete' do
  @game = Game.get params[:id]  
  haml :game_delete
end

post '/game/:id/delete' do
  if params.has_key?("ok")
    game = Game.first(:id => params[:id])
    game.destroy
    redirect '/game'
  else
    redirect '/game'
  end
end


#*************************
#Goals
#*************************
get '/goal' do
  @goals = Goal.all
  @title = 'All Goals'
  haml :goal_form
end

post '/goal' do  
  g = Goal.new  
  g.goal_scorer_id = params[:goal_scorer]
  g.assist1_player_id = params[:assist1_player_id] if params[:assist1_player_id].to_i > 0
  g.assist2_player_id = params[:assist2_player_id] if params[:assist2_player_id].to_i > 0
  g.team_id = params[:team_id]
  g.game_id = params[:game_id]
  g.created_at = Time.now  
  g.updated_at = Time.now  
  if g.save  
    redirect '/ScoreSheet/'+g.game_id.to_s  
  else
    flash[:error] = g.errors.full_messages
	redirect '/ScoreSheet/'+g.game_id.to_s  
  end  
end  

get '/goal/:id' do  
  @goal = Goal.get params[:id]  
  @title = "Edit Goal ##{params[:id]}"  
  haml :goal_edit  
end  

put '/goal/:id' do  
  G = Goal.get params[:id]  
  G.name = params[:name] 
  G.updated_at = Time.now  
  G.save  
  redirect '/goal'  
end  

get '/goal/:id/delete' do
  @goal = Goal.get params[:id]  
  haml :goal_delete
end

post '/goal/:id/delete' do
  if params.has_key?("ok")
    goal = Goal.first(:id => params[:id])
    goal.destroy
    redirect '/ScoreSheet/'+goal.game_id.to_s
  else
    redirect '/ScoreSheet/'+goal.game_id.to_s
  end
end

#*************************
#Penalitys
#*************************
get '/penality' do
  @penalitys = Penality.all
  @title = 'All Penalitys'
  haml :penality_form
end

post '/penality' do  
  g = Penality.new  
  g.player_id = params[:penality]
  g.penality_length = params[:penality_length]
  g.penality_type = params[:penality_type]
  g.team_id = params[:team_id]
  g.game_id = params[:game_id]
  g.created_at = Time.now  
  g.updated_at = Time.now  
  if g.save  
    redirect '/ScoreSheet/'+g.game_id.to_s  
  else
    flash[:error] = g.errors.full_messages
	redirect '/ScoreSheet/'+g.game_id.to_s  
  end  
end  

get '/penality/:id' do  
  @penality = Penality.get params[:id]  
  @title = "Edit Penality ##{params[:id]}"  
  haml :penality_edit  
end  

put '/penality/:id' do  
  G = Penality.get params[:id]  
  G.name = params[:name] 
  G.updated_at = Time.now  
  G.save  
  redirect '/penality'  
end  

get '/penality/:id/delete' do
  @penality = Penality.get params[:id]  
  haml :penality_delete
end

post '/penality/:id/delete' do
  if params.has_key?("ok")
    penality = Penality.first(:id => params[:id])
    penality.destroy
    redirect '/ScoreSheet/'+penality.game_id.to_s
  else
    redirect '/ScoreSheet/'+penality.game_id.to_s
  end
end

#*************************
#Special Pages
#*************************
get '/ScoreSheet/:id' do
  @game = Game.get params[:id]
  @home_players = Player.all(:team_id => @game.home_team.id) 
  @away_players = Player.all(:team_id => @game.away_team.id)
  @gamesplayed = GamePlayed.all(:game_id => @game.id)
  @home_goals = Goal.all(:team_id => @game.home_team.id, :game_id => @game.id)
  @away_goals = Goal.all(:team_id => @game.away_team.id, :game_id => @game.id)
  @goals = Goal.all(:game_id => @game.id)
  @penalities = Penality.all(:game_id => @game.id)
  @title = 'ScoreSheet'
  haml :ScoreSheet
end

get '/stats' do
  @goals = Goal.all
  @players = Player.all
  @teams = Team.all
  @games = Game.all
  haml :stats
end

post '/AddToRoster' do
  r = GamePlayed.new  
  r.roster_player_id = params[:player_id]
  r.team_id = params[:team_id]
  r.game_id = params[:game_id]
  r.created_at = Time.now  
  r.updated_at = Time.now  
  if r.save  
    redirect '/ScoreSheet/'+r.game_id.to_s  
  else
    flash[:error] = r.errors.full_messages
	redirect '/ScoreSheet/'+r.game_id.to_s  
  end  
end

post '/RemoveFromRoster' do
  roster = GamePlayed.first(:id => params[:roster_id])
  roster.destroy
  redirect '/ScoreSheet/'+roster.game_id.to_s  
end

