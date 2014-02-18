require 'spec_helper'

describe "faraday" do
  before(:all) { Bundler.require(:faraday) }
  let!(:key_id)     { (0...8).map{ 65.+(rand(26)).chr}.join }
  let!(:key_secret) { (0...16).map{ 65.+(rand(26)).chr}.join }

  describe "adapter" do
    let!(:adapter)    { Ey::Hmac::Adapter::Faraday }

    it "should sign and read request" do
      request = Faraday::Request.new.tap do |r|
        r.method = :get
        r.path = "/auth"
        r.body = "{1: 2}"
        r.headers = {"Content-Type" => "application/xml"}
        end.to_env(Faraday::Connection.new("http://localhost"))

      Ey::Hmac.sign!(request, key_id, key_secret, adapter: adapter)

      request[:request_headers]['Authorization'].should start_with("EyHmac")
      request[:request_headers]['Content-Digest'].should == Digest::MD5.hexdigest(request[:body])
      Time.parse(request[:request_headers]['Date']).should_not be_nil

      yielded = false

      Ey::Hmac.authenticated?(request, adapter: adapter) do |key_id|
        key_id.should == key_id
        yielded = true
        key_secret
      end.should be_true

      yielded.should be_true
    end

    it "should not set Content-Digest if body is nil" do
      request = Faraday::Request.new.tap do |r|
        r.method = :get
        r.path = "/auth"
        r.body = nil
        r.headers = {"Content-Type" => "application/xml"}
        end.to_env(Faraday::Connection.new("http://localhost"))

      Ey::Hmac.sign!(request, key_id, key_secret, adapter: adapter)

      request[:request_headers]['Authorization'].should start_with("EyHmac")
      request[:request_headers].should_not have_key('Content-Digest')
      Time.parse(request[:request_headers]['Date']).should_not be_nil

      yielded = false

      Ey::Hmac.authenticated?(request, adapter: adapter) do |key_id|
        key_id.should == key_id
        yielded = true
        key_secret
      end.should be_true

      yielded.should be_true
    end

    it "should not set Content-Digest if body is empty" do
      request = Faraday::Request.new.tap do |r|
        r.method = :get
        r.path = "/auth"
        r.body = ""
        r.headers = {"Content-Type" => "application/xml"}
        end.to_env(Faraday::Connection.new("http://localhost"))

      Ey::Hmac.sign!(request, key_id, key_secret, adapter: adapter)

      request[:request_headers]['Authorization'].should start_with("EyHmac")
      request[:request_headers].should_not have_key('Content-Digest')
      Time.parse(request[:request_headers]['Date']).should_not be_nil

      yielded = false

      Ey::Hmac.authenticated?(request, adapter: adapter) do |key_id|
        key_id.should == key_id
        yielded = true
        key_secret
      end.should be_true

      yielded.should be_true
    end

    context "with a request" do
    let!(:request) do
      Faraday::Request.new.tap do |r|
        r.method = :get
        r.path = "/auth"
        r.body = "{1: 2}"
        r.headers = {"Content-Type" => "application/xml"}
      end.to_env(Faraday::Connection.new("http://localhost"))
    end
      include_examples "authentication"
    end
  end

  describe "middleware" do
    it "should accept a SHA1 signature" do
      require 'ey-hmac/faraday'
      Bundler.require(:rack)

      app = lambda do |env|
        authenticated = Ey::Hmac.authenticated?(env, digest: :sha1, adapter: Ey::Hmac::Adapter::Rack) do |auth_id|
          (auth_id == key_id) && key_secret
        end
        [(authenticated ? 200 : 401), {"Content-Type" => "text/plain"}, []]
      end

      request_env = nil
      connection = Faraday.new do |c|
        c.request :hmac, key_id, key_secret, digest: :sha1
        c.adapter(:rack, app)
      end

      connection.get("/resources").status.should == 200
    end

    it "should accept a SHA256 signature" do # default
      require 'ey-hmac/faraday'
      Bundler.require(:rack)

      app = lambda do |env|
        authenticated = Ey::Hmac.authenticated?(env, adapter: Ey::Hmac::Adapter::Rack) do |auth_id|
          (auth_id == key_id) && key_secret
        end
        [(authenticated ? 200 : 401), {"Content-Type" => "text/plain"}, []]
      end

      request_env = nil
      connection = Faraday.new do |c|
        c.request :hmac, key_id, key_secret
        c.adapter(:rack, app)
      end

      connection.get("/resources").status.should == 200
    end

    it "should accept multiple digest signatures" do # default
      require 'ey-hmac/faraday'
      Bundler.require(:rack)

      app = lambda do |env|
        authenticated = Ey::Hmac.authenticated?(env, adapter: Ey::Hmac::Adapter::Rack) do |auth_id|
          (auth_id == key_id) && key_secret
        end
        [(authenticated ? 200 : 401), {"Content-Type" => "text/plain"}, []]
      end

      request_env = nil
      connection = Faraday.new do |c|
        c.request :hmac, key_id, key_secret, digest: [:sha1, :sha256]
        c.adapter(:rack, app)
      end

      connection.get("/resources").status.should == 200
    end

    it "should sign empty request" do
      require 'ey-hmac/faraday'
      Bundler.require(:rack)

      _key_id, _key_secret = key_id, key_secret
      app = Rack::Builder.new do
        use Rack::Config do |env|
          env["CONTENT_TYPE"] ||= "text/html"
        end
        run(lambda {|env|
          authenticated = Ey::Hmac.authenticate!(env, adapter: Ey::Hmac::Adapter::Rack) do |auth_id|
            (auth_id == _key_id) && _key_secret
          end
          [(authenticated ? 200 : 401), {"Content-Type" => "text/plain"}, []]
        })
      end

      request_env = nil
      connection = Faraday.new do |c|
        c.request :hmac, key_id, key_secret
        c.adapter(:rack, app)
      end

      connection.get do |req|
        req.path  = "/resource"
        req.body = nil
        req.params = {"a" => "1"}
        req.headers = {"Content-Type" => "application/x-www-form-urlencoded"}
      end.status.should == 200
    end
  end
end
