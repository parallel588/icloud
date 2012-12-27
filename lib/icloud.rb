require "icloud/version"

require 'faraday'
require 'oj'
require 'uuid'

module ICloud
  URLS = {
		version: "https://www.icloud.com/system/version.json",
		validate: "https://setup.icloud.com",
    # validate: "https://setup.icloud.com/setup/ws/1/validate?clientBuildNumber={0}&clientId={1}",
		authenticate: "https://setup.icloud.com",
    # authenticate: "https://setup.icloud.com/setup/ws/1/login?clientBuildNumber={0}&clientId={1}",
		logout_no_services: "https://setup.icloud.com/setup/ws/1/logout",
		get_contacts_list: "{0}/co/startup?clientBuildNumber={1}&clientId={2}&clientVersion=2.1&dsid={3}&id={4}&locale=en_US&order=last%2Cfirst",
		refresh_web_auth: "{0}/refreshWebAuth?clientBuildNumber={1}&clientId={2}&dsid={3}&id={4}",
		get_notes_list: "{0}/no/startup?clientBuildNumber={1}&clientId={2}&dsid={3}&id={4}",
		get_active_reminders: "{0}/rd/startup?clientVersion=4.0&dsid={1}&id={2}&lang=en-us&usertz=US%2FPacific",
		get_completed_reminders: "{0}/rd/completed?clientVersion=4.0&dsid={1}&id={2}&lang=en-us&usertz=US%2FPacific",
		fmi: nil,
		fmi_init: "{0}/fmipservice/client/web/initClient?dsid={1}&id={2}",
		fmi_refresh: "{0}/fmipservice/client/web/refreshClient?dsid={1}&id={2}",
		get_calendar_events: "{0}/ca/events?clientBuildNumber={1}&clientID={2}&clientVersion=4.0&dsid={3}&endDate={4}&id={5}&lang=en-us&requestID=1&startDate={6}&usertz=US%2FPacific"
	}

  # Your code goes here...
  class Api
    attr_accessor :login, :password, :instance, :auth

    def initialize(login, password)
      @login = login
      @password = password
      @auth = nil
      @instance = nil
    end

    def client_build_number
      version["buildNumber"]
    end
    def client_id
      @uuid ||= UUID.new.generate.upcase
    end

    def dequote(str)
      ret = (/\A"(.*)"\Z/ =~ str) ? $1 : str.dup
      ret.gsub!(/\\(.)/, "\\1")
      ret
    end

    def webservices
      Oj.load((@auth && @auth.body)||"{}")['webservices']
    end

    def ds_info
      Oj.load((@auth && @auth.body)||"{}")['dsInfo']
    end

    def apps
      Oj.load((@auth && @auth.body)||"{}")['apps']
    end

    def dequote(str)
      ret = (/\A"(.*)"\Z/ =~ str) ? $1 : str.dup
      ret.gsub!(/\\(.)/, "\\1")
      ret
    end

    def cookie=(v)

      @cookie = v.to_s.split(/,(?=[^;,]*=)|,$/).map { |c|
        cookie_elem = c.split(/;+/)
        first_elem = cookie_elem.shift
        first_elem.strip!
        key, value = first_elem.split(/\=/, 2)

        cookie = { 'name' =>key, 'value' =>  value.dup }


        cookie_elem.each do |pair|
          pair.strip!
          key, value = pair.split(/=/, 2)
          next unless key
          value = dequote(value.strip) if value

          case key.downcase
          when 'domain'
            next unless value && !value.empty?
            begin
              cookie['domain'] = value
              cookie['for_domain'] = true
            rescue
              puts ("Couldn't parse domain: #{value}")
            end
          when 'path'
            next unless value && !value.empty?
            cookie['path'] = value
          when 'expires'
            next unless value && !value.empty?
            begin
              cookie['expires'] = Time::parse(value)
            rescue
              puts "Couldn't parse expires: #{value}"
            end
          when 'max-age'
            next unless value && !value.empty?
            begin
              cookie['max_age'] = Integer(value)
            rescue
              puts "Couldn't parse max age '#{value}'"
            end
          when 'comment'
            next unless value
            cookie['comment'] = value
          when 'version'
            next unless value
            begin
              cookie['version'] = Integer(value)
            rescue
              puts "Couldn't parse version '#{value}'"
              cookie['version'] = nil
            end
          when 'secure'
            cookie['secure'] = true
          end
        end

        cookie['secure']  ||= false


        # RFC 6265 4.1.2.2
        cookie['expires']   = Time.now + cookie['max_age']  if cookie['max_age']
        cookie['session']   = !cookie['expires']

        # Move this in to the cookie jar
        cookie
      }.map{|j| "#{j['name']}=#{j['value']}"}.join(';')

    end

    def cookie
      @cookie.to_s
    end

    def instance=(v)
      @instance = v
    end

    def instance
      @instance
    end


    def version
      @version_resp ||= Faraday.get(URLS[:version])
      Oj.load(@version_resp.body)
    end

    def validate
      conn = Faraday.new(:url => URLS[:validate])

      resp = conn.post do |req|
        req.url '/setup/ws/1/validate'
        req.headers["Origin"] =  "https://www.icloud.com"
        req.headers["Referer"] = "https://www.icloud.com"
        req.headers["Cookie"]  = cookie
        req.params = { "clientBuildNumber" => client_build_number, "clientId" => client_id}
      end
      self.cookie = resp.env[:response_headers]["set-cookie"] if resp.env[:response_headers].has_key?("set-cookie")
      self.instance = Oj.load(resp.body)['instance']

      resp

    end

    def authenticate?
      !!@auth
    end

    def authenticate(remember_me = false)
      @auth ||
        begin
          validate
          conn = Faraday.new(:url => ICloud::URLS[:authenticate])
          checksum = Digest::SHA1.hexdigest([login, instance].join).upcase

          auth_params = {
          "apple_id" => login,
          "password" => password,
          "id" => checksum,
          "extended_login" => remember_me
        }

          @auth = conn.post do |req|
          req.url '/setup/ws/1/login'
          req.headers["Origin"] =  "https://www.icloud.com"
          req.headers["Referer"] = "https://www.icloud.com"
          req.headers["Cookie"]  = cookie
          req.params = { "clientBuildNumber" => client_build_number, "clientId" => client_id}
          req.body = Oj.dump(auth_params)
        end

          self.cookie = @auth.env[:response_headers]["set-cookie"]
          self.instance = Oj.load(@auth.body)['instance']

        end

      @auth
    end

    def contacts
      authenticate unless authenticate?

      @contacts ||
        begin
          conn = Faraday.new(:url => webservices["contacts"]["url"] )
          checksum = Digest::SHA1.hexdigest([login, instance].join).upcase

          resp = conn.get do |req|
          req.url '/co/startup'
          req.headers["Origin"] =  "https://www.icloud.com"
          req.headers["Referer"] = "https://www.icloud.com"
          req.headers["Cookie"]  = cookie
          req.params = {
            "clientBuildNumber" => client_build_number,
            "clientId" => client_id,
            "dsid" => ds_info['dsid'],
            "clientVersion" => '2.1',
            "locale" => 'en_US',
            "order" => 'last,first',
            "id" => checksum
          }
          end

          @contacts = Oj.load(resp.body)
        end

      @contacts
    end

  end
end
