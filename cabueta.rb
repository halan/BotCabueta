require 'cinch'
require 'twitter_oauth'

module Config
  @@CONFIG_FILE = 'config.yml'

  def self.get
    YAML::load_file @@CONFIG_FILE
  end

  def self.put content
    File.open(@@CONFIG_FILE, 'w') do |f|
      f.write content
    end
  end
end

class TwitterClient
  attr_accessor :client

  def initialize config
    unless config['twitter'][:secret] and config['twitter'][:token]

      @client = TwitterOAuth::Client.new config['twitter']
      request_token = twitter_client.request_token
      puts "Authorize => #{request_token.authorize_url}"
      puts 'Verifier:'
      verifier = gets

      access_token = client.authorize request_token.token, request_token.secret, :oauth_verifier => verifier.strip
      unless twitter_client.authorized?
        puts 'Authorization failed'
        exit
      else
        Config.put (config['twitter'].merge( :token => access_token.token, :secret => access_token.secret)).to_yaml
      end
    else
      @client = TwitterOAuth::Client.new config['twitter']
    end

    exit unless @client.authorized?
  end
end

@@twitter = TwitterClient.new(Config::get).client 

class TwitterPlugin
  include Cinch::Plugin
  attr_accessor :timeline, :last_id

  timer 10, method: :show_tweet
  def show_tweet
    tweet = last_tweet
    if tweet and tweet['user']['screen_name'] != @@twitter.info['screen_name']
      Channel(Config::get['irc']['channel']).send "@#{tweet['user']['screen_name']}: #{tweet['text']}" if tweet
    end
  rescue
    nil
  end

  timer 60*40, method: :about
  def about
    Channel(Config::get['irc']['channel']).send @@twitter.info['description']
  rescue
    nil
  end

  timer 60*20, method: :followme
  def followme
    Channel(Config::get['irc']['channel']).send "Me siga em: http://twitter.com/#{@@twitter.info['screen_name']}"
  rescue
    nil
  end

  def load_timeline
    @timeline ||= []

    if @last_id
      @timeline = @@twitter.friends_timeline(:since_id => @last_id, :include_rts => true) + @timeline
    else
      @timeline = @@twitter.friends_timeline(:include_rts => true, :count => 1) + @timeline
    end
  end

  def last_tweet
    load_timeline if not @timeline or @timeline.empty?

    tweet = @timeline.last
    @last_id = tweet['id_str']
    @timeline.delete tweet

    return tweet
  rescue
    nil
  end

  listen_to :channel
  def listen m
    return unless @@twitter.authorized?
    @@twitter.update "#{m.user.nick}: #{m.message}".gsub /\x03[0-9]{,2}(,[0-9]{,2})?/, ''
  rescue
    nil
  end
end



bot = Cinch::Bot.new do
  configure do |c|
    c.nick            = Config::get['irc']['nick']
    c.server          = Config::get['irc']['server']
    c.channels        = [Config::get['irc']['channel']]
    c.verbose         = true
    c.plugins.plugins = [TwitterPlugin]
  end
end

bot.start
