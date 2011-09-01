require "net/http/persistent"
require "rexml/document"
require "base64"
require "time"

# Simpler AWS S3 library
class S4
  VERSION = "0.0.2"

  # sub-resource names which may appear in the query string and also must be
  # signed against.
  SubResources = %w( acl location logging notification partNumber policy requestPayment torrent uploadId uploads versionId versioning versions website )

  # Header over-rides which may appear in the query string and also must be
  # signed against.
  HeaderValues = %w( response-content-type response-content-language response-expires reponse-cache-control response-content-disposition response-content-encoding )

  attr_reader :connection, :access_key_id, :secret_access_key, :bucket, :host
  
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
    #   bucket = S4.connect("s3://0PN5J17HBGZHT7JJ3X82:k3nL7gH3+PadhTEVn5EXAMPLE@s3.amazonaws.com/bucket")
    def connect(s3_url=ENV["S3_URL"])
      new(s3_url).tap do |s4|
        s4.connect
      end
    end
    
    # Create an S3 bucket.
    # 
    # See #connect for S3_URL parameters.
    # 
    # Will create the bucket on S3 and connect to it, or just connect if the
    # bucket already exists and is owned by you.
    # 
    # i.e.
    #   bucket = S4.create
    def create(s3_url=ENV["S3_URL"])
      new(s3_url).tap do |s4|
        s4.create
      end
    end
  end
  
  # Initialize a new S3 bucket connection.
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
    raise NoSuchBucket.new(bucket) if request(uri("/", query: "location")).nil?
  end
  
  # Create the S3 bucket.
  def create
    uri = URI::HTTP.build(host: host, path: "/#{bucket}")
    request uri, Net::HTTP::Put.new(uri.request_uri)
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
  
  def put(io, name)
    uri = uri(name)
    req = Net::HTTP::Put.new(uri.request_uri)

    req.body_stream = io
    req.add_field "Content-Length", io.size
    req.add_field "Content-Type", "application/x-www-form-urlencoded"

    request(URI::HTTP.build(host: host, path: "/#{bucket}/#{name}"), req)
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
        raise Error.from_response(response)
      end
    end
  end

  def sign(uri, request)
    date = Time.now.utc.rfc822

    request.add_field "Date", date
    request.add_field "Authorization", "AWS #{access_key_id}:#{signature(uri, request)}"

    request
  end

  def signature(uri, request)
    query = signed_params(uri.query) if uri.query
    
    Base64.encode64(
      OpenSSL::HMAC.digest(
        OpenSSL::Digest::Digest.new("sha1"),
        secret_access_key,
        "#{request.class::METHOD}\n\n#{request["Content-Type"]}\n#{request.fetch("Date")}\n" + uri.path + (query ? "?#{query}"  : "")
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
      join("&")
      
    signed unless signed.empty?
  end
  
  # Base class of all S3 Errors
  class Error < ::RuntimeError
    attr_reader :code, :status
    
    def self.from_response(response)
      doc = REXML::Document.new(response.body).elements["//Error"]
      code = doc.elements["Code"].text
      message = doc.elements["Message"].text
      
      new response.code, code, message
    end
    
    def initialize(status, code, message)
      @status = status
      @code = code
      
      super "#{@code}: #{message}"
    end
  end  
end
