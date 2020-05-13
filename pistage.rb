require "sinatra/base"
require "json"
require "net/http"
require "pit"

# RUN this program
# RUN smee 
#   smee -u https://smee.io/XXXXXXX -p 8080 -P /smee
# IFTTT setting
#   1. Google Assistant "Start dance mode" => webhook POST "https://smee.io/XXXXXXX?request=start"
#   2. Google Assistant "Stop dance mode" => webhook POST "https://smee.io/XXXXXXX?request=stop"
#   3. Webhook POST "ceiling_light_(on|off) => ratoc ceiling light on|off
#   4. Webhook POST "pistage01_webhook_hs105_on|off => kasa on|off

class StageController
    BASE_DIR = "/home/pi/Data"
    MUSICS = {
        "stayinalive" => "#{BASE_DIR}/stayin_alive.mp3",
        "cannedheat" => "#{BASE_DIR}/cannedheat.mp3",
    }
    DEFAULT_MUSIC = MUSICS.keys[0]

    WEBHOOK_PREFIX = "https://maker.ifttt.com/trigger/"
    WEBHOOK_SUFFIX = "/with/key/"

    WEBHOOK_URL_STAGE_LIGHT_ONOFF = {
        true =>  "pistage01_webhook_hs105_on",
        false => "pistage01_webhook_hs105_off"
    }

    WEBHOOK_URL_CEILING_LIGHT_ONOFF = {
        true =>  "ceiling_light_on",
        false => "ceiling_light_off"
    }

    def initialize
        @thread = nil
        @key = Pit.get("ifttt")[:key]

    end

    def status
        msg = {}
        msg[:running] = @thread.nil? ? false : @thrad.alive?
        msg[:music_name] = MUSICS.keys
        return msg
    end

    def start args
        if @thread != nil and @thread.alive?
            raise "thread is already running"
        end

        music_path = MUSICS[args["name"]] || MUSICS[MUSICS.keys[rand(MUSICS.length)]]

        @thread = Thread.new do
            set_ceiling_light(false)
            set_stage_light(true)
            play_music(music_path)
            set_stage_light(false)
            set_ceiling_light(true)
        end

        nil 
    end

    def stop
        if @thread and @thread.alive?
            @thread.kill
        end
        stop_music()
        set_stage_light(false)
        set_ceiling_light(true)
    end

    private
    def request_webhook(elm)
        url = WEBHOOK_PREFIX + elm + WEBHOOK_SUFFIX + @key
        uri = URI.parse(url)
        req = Net::HTTP::Post.new(uri)
        req_options = {
            use_ssl: uri.scheme == "https"
        }

        resp = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
            http.request(req)
        end

    end

    def set_stage_light(on=true)
        request_webhook(WEBHOOK_URL_STAGE_LIGHT_ONOFF[on == true])
    end

    def set_ceiling_light(on=true)
        request_webhook(WEBHOOK_URL_CEILING_LIGHT_ONOFF[on == true])
    end


    def play_music(path)
        system("/usr/bin/mpg321 #{path}")
    end

    def stop_music()
        system("killall mpg321")
    end
end

class APIServer < Sinatra::Base
    DEFAULT_PORT=8080

    set :port, DEFAULT_PORT
    enable :logging

    def self.run! args={}
        @@arg = args
        @@port = args[:port] || DEFAULT_PORT
        set :port, @port
        set :bind, "0.0.0.0"
        set :logging, true
        set :dump_errors, true
        set :environment, :production

        @@stage = StageController.new

        super
    end

    def self.log msg
        puts msg
    end

    def self.start(data={})
        json = if data.nil? or data.empty?
            {}
        elsif data.is_a?(String)
            JSON.parse(data)
        else
            data
        end

        @@stage.start(json)
        nil
    end

    def self.stop()
        @@stage.stop
    end

    def self.status()
        return @@stage.status.to_json
    end

    get "/" do
        redirect to ("/status")
    end

    get "/smee" do
        content_type :json
        return APIServer.status()
    end
    
    post "/smee" do
        p request
        logger.info "/smee in"
        begin
            msg = {
                "request" => params["request"],
                "name" => params["name"]
            }

            case msg["request"]
            when "start"
                APIServer.start(msg)
            when "stop"
                APIServer.stop()
            else
                raise "no such requet method"
            end

            status 200
        rescue => e
            logger.error "/smee: failed to process request (#{e})"
            status 500
        end
    end

    get "/status" do
        content_type :json
        return APIServer.status()
    end

    post "/stage/v1/start" do
        logger.info "/statge/v1/start in"
        begin
            APIServer.start(request.body.read)
            status 200
        rescue => e
            logger.error "/stage/v1/start: failed to process request (#{e})"
            status 500
        end
    end

    post "/stage/v1/stop" do
        APIServer.stop()
    end
end

if __FILE__ == $0
    APIServer.run!
end
