require 'spec_helper'

describe "rack" do
  before(:all) { Bundler.require(:rack) }

  let!(:key_id)     { SecureRandom.hex(8) }
  let!(:key_secret) { SecureRandom.hex(16) }

  describe "adapter" do
    let(:adapter)     { Ey::Hmac::Adapter::Rack }

    it "should sign and read request" do
      request = Rack::Request.new(
        "rack.input"        => StringIO.new("{1: 2}"),
        "HTTP_CONTENT_TYPE" => "application/json",
      )
      Ey::Hmac.sign!(request, key_id, key_secret, adapter: adapter)

      request.env['HTTP_AUTHORIZATION'].should start_with("EyHmac")
      request.env['HTTP_CONTENT_DIGEST'].should == Digest::MD5.hexdigest(request.body.tap(&:rewind).read)
      Time.parse(request.env['HTTP_DATE']).should_not be_nil

      yielded = false

      Ey::Hmac.authenticated?(request, adapter: adapter) do |key_id|
        key_id.should == key_id
        yielded = true
        key_secret
      end.should be_true

      yielded.should be_true
    end

    it "should not set Content-Digest if body is nil" do
      request = Rack::Request.new(
        "HTTP_CONTENT_TYPE" => "application/json",
      )

      Ey::Hmac.sign!(request, key_id, key_secret, adapter: adapter)

      request.env['HTTP_AUTHORIZATION'].should start_with("EyHmac")
      request.env.should_not have_key('HTTP_CONTENT_DIGEST')
      Time.parse(request.env['HTTP_DATE']).should_not be_nil

      yielded = false

      Ey::Hmac.authenticated?(request, adapter: adapter) do |key_id|
        key_id.should == key_id
        yielded = true
        key_secret
      end.should be_true

      yielded.should be_true
    end

    it "should not set Content-Digest if body is empty" do
      request = Rack::Request.new(
        "rack.input"        => StringIO.new(""),
        "HTTP_CONTENT_TYPE" => "application/json",
      )

      Ey::Hmac.sign!(request, key_id, key_secret, adapter: adapter)

      request.env['HTTP_AUTHORIZATION'].should start_with("EyHmac")
      request.env.should_not have_key('HTTP_CONTENT_DIGEST')
      Time.parse(request.env['HTTP_DATE']).should_not be_nil

      yielded = false

      Ey::Hmac.authenticated?(request, adapter: adapter) do |key_id|
        key_id.should == key_id
        yielded = true
        key_secret
      end.should be_true

      yielded.should be_true
    end

    context "with a request" do
      let(:request) {
        Rack::Request.new(
          "rack.input"        => StringIO.new("{1: 2}"),
          "HTTP_CONTENT_TYPE" => "application/json",
        )
      }

      include_examples "authentication"
    end
  end

  describe "middleware" do
    it "should accept a SHA1 signature" do
      app = lambda do |env|
        authenticated = Ey::Hmac.authenticated?(env, digest: :sha1, adapter: Ey::Hmac::Adapter::Rack) do |auth_id|
          (auth_id == key_id) && key_secret
        end
        [(authenticated ? 200 : 401), {"Content-Type" => "text/plain"}, []]
      end

      _key_id, _key_secret = key_id, key_secret
      client = Rack::Client.new do
        use Ey::Hmac::Rack, _key_id, _key_secret, digest: :sha1
        run app
      end
    end

    it "should accept a SHA256 signature" do # default
      app = lambda do |env|
        authenticated = Ey::Hmac.authenticated?(env, adapter: Ey::Hmac::Adapter::Rack) do |auth_id|
          (auth_id == key_id) && key_secret
        end
        [(authenticated ? 200 : 401), {"Content-Type" => "text/plain"}, []]
      end

      _key_id, _key_secret = key_id, key_secret
      client = Rack::Client.new do
        use Ey::Hmac::Rack, _key_id, _key_secret
        run app
      end

      client.get("/resource").status.should == 200
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
  end
end
