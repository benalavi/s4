require "net/http/persistent"
require "nokogiri"
require "base64"
require "time"

# Simpler AWS S3 library
class S3
  # sub-resource names which may appear in the query string and also must be
  # signed against.
  SubResources = %w( acl location logging notification partNumber policy requestPayment torrent uploadId uploads versionId versioning versions website )

  # Header over-rides which may appear in the query string and also must be
  # signed against.
  HeaderValues = %w( response-content-type response-content-language response-expires reponse-cache-control response-content-disposition response-content-encoding )

  attr_reader :connection, :access_key_id, :secret_access_key, :bucket, :host

  def initialize(s3_url = ENV["S3_URL"])
    raise ArgumentError, "No S3 URL provided. You can set ENV['S3_URL'], too." if s3_url.nil? || s3_url.empty?

    begin
      url = URI(s3_url)
    rescue URI::InvalidURIError => e
      e.message << " The format is s3://access_key_id:secret_access_key@s3.amazonaws.com/bucket"
      raise e
    end

    @access_key_id     = url.user
    @secret_access_key = URI.unescape(url.password || "")
    @host              = url.host
    @bucket            = url.path[1..-1]
  end

  def connection
    @connection ||= Net::HTTP::Persistent.new("aws-s3/#{bucket}")
  end

  # Lower level object get which just yields the successful S3 response to the
  # block. See #download if you want to simply copy a file from S3 to local.
  def get(name, &block)
    request(uri(name), &block)
  end

  # Download the file with the given filename to the given destination.
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

  # Upload the file with the given filename to the given destination in your
  # S3 bucket. If no destination is given then uploads it with the same
  # filename to the root of your bucket.
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

  # List bucket contents
  def list(prefix="")
    Nokogiri::XML.parse(request(uri("", query: "prefix=#{prefix}"))).search("Key").collect(&:text)
  end

  private

  def uri(path, options={})
    URI::HTTP.build(options.merge(host: host, path: "/#{bucket}/#{CGI.escape(path.sub(/^\//, ""))}"))
  end

  # Makes a request to the S3 API and returns the Nokogiri-parsed XML
  # response.

  def request(uri, request = nil)
    # TODO: Possibly use SAX parsing for large request bodies (?)

    request ||= Net::HTTP::Get.new(uri.request_uri)

    connection.request(uri, sign(uri, request)) do |response|
      case response
        when Net::HTTPNotFound
          return nil

        when Net::HTTPSuccess
          if block_given?
            yield(response)
          else
            return response.body
          end

        else
          raise Error.from_xml(Nokogiri::XML.parse(response.body).at("Error"))

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
    Base64.encode64(
      OpenSSL::HMAC.digest(
        OpenSSL::Digest::Digest.new("sha1"),
        secret_access_key,
        "#{request.class::METHOD}\n\n#{request["Content-Type"]}\n#{request.fetch("Date")}\n#{uri.path}"
      )
    ).chomp
  end

  # Base class of all S3 Errors
  class Error < ::RuntimeError
    # Factory for various Error types based on the given XML. We get a
    # uniform error response back from AWS, so rather than redefine all of
    # their error types, can just dynamically generate them when they occur
    # and define any special cases we want.
    #
    # Dynamically generates the exception class based on the given "Code"
    # value in the XML (unless it's been previously defined).
    #
    # i.e.
    #
    # Error.from_xml <<-ERROR
    # <Error>
    #   <Code>FooError</Code>
    #   <Message>Foo!</Message>
    # </Error>
    # ERROR #=> returns FooError.new("Foo!")
    #
    def self.from_xml(xml)
      S3.const_set(xml.at("Code").text, Class.new(Error)) unless S3.const_defined?(xml.at("Code").text)
      S3.const_get(xml.at("Code").text).new(xml.at("Message").text)
    end
  end
end
