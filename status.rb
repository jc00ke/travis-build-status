require 'goliath'
require 'em-synchrony/em-http'
require 'em-http/middleware/json_response'
require 'yajl'

EM::HttpRequest.use EventMachine::Middleware::JSONResponse

class Status < Goliath::API
  use Goliath::Rack::Params
  use Goliath::Rack::Formatters::JSON
  use Goliath::Rack::Render

  def response(env)
    owner_name = params['owner-name']
    repo_name = params['repo-name']
    ruby_engine = params['ruby-engine']

    status = TravisStatus.new(owner_name, repo_name, ruby_engine, logger)


    [302, { 'Content-Type' => 'image/png', 'Location' => status.image_url }, status.state]
  end
end

class TravisStatus
  attr_reader :owner_name, :repo_name, :ruby_engine, :logger, :latest_build, :state, :the_job

  def initialize(owner_name, repo_name, ruby_engine, logger=STDOUT)
    @owner_name = owner_name
    @repo_name = repo_name
    @ruby_engine = ruby_engine
    @logger = logger
    fetch_details
  end

  def image_url
    "https://raw.github.com/gittip/shields.io/master/static/travis/travis_#{state}.png"
  end

  private

  def get_latest_build
    @latest_build ||= get_json("/builds/#{@last_build_id}")
  end

  def get_builds
    @builds ||= get_json("/repos/#{owner_name}/#{repo_name}/builds")
  end

  def fetch_details
    begin
      get_builds
      @last_build_id = @builds.first.fetch("id")
      get_latest_build
      get_the_job
      @result = get_result
      @state = get_state
    rescue Object
      @state = "unknown"
    end
  end

  def get_state
    if @result == 0
      "passing"
    elsif @result == 1
      "failing"
    else
      "unknown"
    end
  end

  def get_the_job
    @the_job = matrix.detect { |job|
      job["config"]["rvm"] == ruby_engine
    }
  end

  def matrix
    latest_build.fetch("matrix")
  end

  def get_result
    if the_job
      the_job.fetch("result")
    else
      -1
    end
  end

  def get_json(url)
    req = get_travis_url(url)
    req.response
  end

  def get_travis_url(url)
    EM::HttpRequest.new("https://api.travis-ci.org#{url}").get
  end

  def log(msg)
    logger.info "*" * 50
    logger.info msg.inspect
    logger.info "*" * 50
  end
end

class InvalidTravisResponse < StandardError; end
