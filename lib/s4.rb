require "net/http/persistent"
require "rexml/document"
require "base64"
require "time"
require "json"
require "shellwords"

# Simpler AWS S3 library
class S4
  VERSION = "0.0.5"

  # sub-resource names which may appear in the query string and also must be
  # signed against.
  SubResources = %w( acl location logging notification partNumber policy requestPayment torrent uploadId uploads versionId versioning versions website )

  # Header over-rides which may appear in the query string and also must be
  # signed against (in addition those which begin w/ 'x-amz-')
  HeaderValues = %w( response-content-type response-content-language response-expires reponse-cache-control response-content-disposition response-content-encoding )

  # List of available ACLs on buckets, first is used as default
  # http://docs.amazonwebservices.com/AmazonS3/latest/API/index.html?RESTBucketPUT.html
  BucketACLs = %w( private public-read public-read-write authenticated-read bucket-owner-read bucket-owner-full-control )

  # Named policies
  Policy = {
    public_read: %Q{\{
      "Version": "2008-10-17",
      "Statement": [{
        "Sid": "AllowPublicRead",
        "Effect": "Allow",
        "Principal": {"AWS": "*"},
        "Action": ["s3:GetObject"],
        "Resource": ["arn:aws:s3:::%s/*"]
      }]
    \}}
  }.freeze

  attr_reader :connection, :access_key_id, :secret_access_key, :bucket, :host

  # Cannot call #new explicitly (no reason to), use #connect instead
  private_class_method :new

  class << self
    # Connect to an S3 bucket.
    #
    # Pass your S3 connection parameters as URL, or read from ENV["S3_URL"] if
    # none is passed.
    #
    # S3_URL format is s3://<access key id>:<secret access key>@s3.amazonaws.com/<bucket>
    #
    # i.e.
    #   bucket = S4.connect #=> Connects to ENV["S3_URL"]
    #   bucket = S4.connect(url: "s3://0PN5J17HBGZHT7JJ3X82:k3nL7gH3+PadhTEVn5EXAMPLE@s3.amazonaws.com/bucket")
    def connect(options={})
      init(options) do |s4|
        s4.connect
      end
    end

    # Create a new S3 bucket.
    #
    # See #connect for S3_URL parameters.
    #
    # Will create the bucket on S3 and connect to it, or just connect if the
    # bucket already exists and is owned by you.
    #
    # i.e.
    #   bucket = S4.create
    def create(options={})
      init(options) do |s4|
        s4.create(options[:acl] || BucketACLs.first)
      end
    end

    private

    def init(options={}, &block)
      new(options.has_key?(:url) ? options[:url] : ENV["S3_URL"]).tap do |s4|
        yield(s4) if block_given?
      end
    end
  end

  def initialize(s3_url=ENV["S3_URL"])
    raise ArgumentError, "No S3 URL provided. You can set ENV['S3_URL'], too." if s3_url.nil? || s3_url.empty?

    begin
      url = URI(s3_url)
    rescue URI::InvalidURIError => e
      e.message << " The format is s3://access_key_id:secret_access_key@s3.amazonaws.com/bucket"
      raise e
    end

    @access_key_id = url.user
    @secret_access_key = URI.unescape(url.password || "")
    @host = url.host
    @bucket = url.path[1..-1]
  end

  # Connect to the S3 bucket.
  #
  # Since S3 doesn't really require a persistent connection this really just
  # makes sure that it *can* connect (i.e. the bucket exists and you own it).
  def connect
    location
  end

  # Create the S3 bucket.
  #
  # If the bucket exists and you own it will not do anything, if it exists and
  # you don't own it will raise an error.
  #
  # Optionally pass an ACL for the new bucket, see BucketACLs for valid ACLs.
  #
  # Default ACL is "private"
  def create(acl=BucketACLs.first)
    raise ArgumentError.new("Invalid ACL '#{acl}' for bucket. Available ACLs are: #{BucketACLs.join(", ")}.") unless BucketACLs.include?(acl)

    uri = uri("/")
    req = Net::HTTP::Put.new(uri.request_uri)

    req.add_field "x-amz-acl", acl

    request uri, req
  end

  # Lower level object get which just yields the successful S3 response to the
  # block. See #download if you want to simply copy a file from S3 to local.
  def get(name, &block)
    request(uri(name), &block)
  rescue S4::Error => e
    raise e if e.status != "404"
  end

  # Download the file with the given filename to the given destination.
  #
  # i.e.
  #   bucket.download("images/palm_trees.jpg", "./palm_trees.jpg")
  def download(name, destination=nil)
    get(name) do |response|
      File.open(destination || File.join(Dir.pwd, File.basename(name)), "wb") do |io|
        response.read_body do |chunk|
          io.write(chunk)
        end
      end
    end
  end

  # Delete the object with the given name.
  def delete(name)
    request(uri = uri(name), Net::HTTP::Delete.new(uri.request_uri))
  end

  # Upload the file with the given filename to the given destination in your S3
  # bucket.
  #
  # If no destination is given then uploads it with the same filename to the
  # root of your bucket.
  #
  # i.e.
  #   bucket.upload("./images/1996_animated_explosion.gif", "website_background.gif")
  def upload(name, destination=nil)
    put File.open(name, "rb"), destination || File.basename(name)
  end

  # Write an IO stream to a file in this bucket.
  #
  # Will write file with content_type if given, otherwise will attempt to
  # determine content type by shelling out to POSIX `file` command (if IO
  # stream responds to #path). If no content_type could be determined, will
  # default to application/x-www-form-urlencoded.
  #
  # i.e.
  #   bucket.put(StringIO.new("Awesome!"), "awesome.txt", "text/plain")
  def put(io, name, content_type=nil)
    uri = uri(name)
    req = Net::HTTP::Put.new(uri.request_uri)

    content_type = `file -ib #{Shellwords.escape(io.path)}`.chomp if !content_type && io.respond_to?(:path)

    req.add_field "Content-Type", content_type
    req.add_field "Content-Length", io.size
    req.body_stream = io

    target_uri = uri("/#{name}")

    request(target_uri, req)

    target_uri.to_s
  end

  # List bucket contents.
  #
  # Optionally pass a prefix to list from (useful for paths).
  #
  # i.e.
  #   bucket.list("images/") #=> [ "birds.jpg", "bees.jpg" ]
  def list(prefix = "")
    REXML::Document.new(request(uri("", query: "prefix=#{prefix}"))).elements.collect("//Key", &:text)
  end

  # Turns this bucket into a S3 static website bucket.
  #
  # IMPORTANT: by default a policy will be applied to the bucket allowing read
  # access to all files contained in the bucket.
  #
  # i.e.
  #   site = S4.connect(url: "s3://0PN5J17HBGZHT7JJ3X82:k3nL7gH3+PadhTEVn5EXAMPLE@s3.amazonaws.com/mywebsite")
  #   site.website!
  #   site.put(StringIO.new("<!DOCTYPE html><html><head><title>Robots!</title></head><body><h1>So many robots!!!</h1></body></html>", "r"), "index.html")
  #   Net::HTTP.get(URI.parse("http://mywebsite.s3.amazonaws.com/")) #=> ...<h1>So many robots!!!</h1>...
  def website!
    self.policy = Policy[:public_read] % bucket

    uri = uri("/", query: "website")
    req = Net::HTTP::Put.new(uri.request_uri)

    req.body = <<-XML
    <WebsiteConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
      <IndexDocument>
        <Suffix>index.html</Suffix>
      </IndexDocument>
      <ErrorDocument>
        <Key>404.html</Key>
      </ErrorDocument>
    </WebsiteConfiguration>
    XML

    request uri, req
  end

  # The URL of the bucket for use as a website.
  def website
    "#{bucket}.s3-website-#{location}.amazonaws.com"
  end

  # Sets the given policy on the bucket.
  #
  # Policy can be given as a string which will be applied as given, a hash
  # which will be converted to json, or the name of a pre-defined policy as a
  # symbol.
  #
  # See S4::Policy for pre-defined policies.
  #
  # i.e.
  #   $s4 = S4.connect
  #   $s4.policy = :public_read #=> apply named policy
  #   $s4.policy = {"Statement" => "..."} #=> apply policy as hash
  #   $s4.policy = "{\"Statement\": \"...\"}" #=> apply policy as string
  def policy=(policy)
    policy = Policy[policy] % bucket if policy.is_a?(Symbol)

    uri = uri("/", query: "policy")
    req = Net::HTTP::Put.new(uri.request_uri)

    req.body = policy.is_a?(String) ? policy : policy.to_json

    request uri, req
  end

  # Gets the policy on the bucket.
  def policy
    request uri("/", query: "policy")
  end

  # Gets information about the buckets location.
  def location
    response = request uri("/", query: "location")
    location = REXML::Document.new(response).elements["LocationConstraint"].text

    location || "us-east-1"
  end

  def inspect
    "#<S4: bucket='#{bucket}'>"
  end

  private

  def connection
    @connection ||= Net::HTTP::Persistent.new("aws-s3/#{bucket}")
  end

  def uri(path, options={})
    URI::HTTP.build(options.merge(host: host, path: "/#{bucket}/#{URI.escape(path.sub(/^\//, ""))}"))
  end

  # Makes a request to the S3 API.
  def request(uri, request=nil)
    request ||= Net::HTTP::Get.new(uri.request_uri)

    connection.request(uri, sign(uri, request)) do |response|
      case response
      when Net::HTTPSuccess
        if block_given?
          yield(response)
        else
          return response.body
        end
      else
        raise Error.new(response)
      end
    end
  end

  def sign(uri, request)
    date = Time.now.utc.rfc822

    request.add_field "Date", date
    request.add_field "Content-Type", "application/x-www-form-urlencoded" if request.is_a?(Net::HTTP::Put) && !request["Content-Type"]

    request.add_field "Authorization", "AWS #{access_key_id}:#{signature(uri, request)}"
    request
  end

  def signature(uri, request)
    query = signed_params(uri.query) if uri.query

    string_to_sign = "#{request.class::METHOD}\n\n#{request["Content-Type"]}\n#{request["Date"]}\n#{canonicalized_headers(request)}" + "#{uri.path}" + (query ? "?#{query}"  : "")

    Base64.encode64(
      OpenSSL::HMAC.digest(
        OpenSSL::Digest::Digest.new("sha1"),
        secret_access_key,
        string_to_sign
      )
    ).chomp
  end

  # Returns the given query string consisting only of query parameters which
  # need to be signed against, or nil if there are none in the query string.
  def signed_params(query)
    signed = query.
      split("&").
      collect{ |param| param.split("=") }.
      reject{ |pair| !SubResources.include?(pair[0]) }.
      collect{ |pair| pair.join("=") }.
      sort.
      join("&")

    signed unless signed.empty?
  end

  def canonicalized_headers(request)
    headers = request.to_hash.
      reject{ |k, v| k !~ /x-amz-/ && !HeaderValues.include?(k) }.
      collect{ |k, v| "#{k}:#{v.join(",")}" }.
      sort.
      join("\n")

    "#{headers}\n" unless headers.empty?
  end

  # Base class of all S3 Errors
  class Error < ::RuntimeError
    attr_reader :code, :status, :response

    def initialize(response)
      @response = REXML::Document.new(response.body).elements["//Error"]

      @status = response.code
      @code = @response.elements["Code"].text

      super "#{@status}: #{@code} -- " + @response.elements["Message"].text
    end
  end
end
