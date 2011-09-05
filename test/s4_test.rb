raise "You need to have ENV[\"S3_URL\"] set for the tests to connect to your testing bucket on S3. Format is: 's3://<access key id>:<secret access key>@s3.amazonaws.com/<s4 test bucket>'." unless ENV["S3_URL"]
raise "You need to have ENV[\"S4_NEW_BUCKET\"], which will be dynamically created and destroyed for testing bucket creation. i.e.: 's4-test-bucketthatdoesntexist'." unless ENV["S3_URL"]

require "contest"
require "timecop"
require "fileutils"
require "open-uri"

begin
  require "ruby-debug"
rescue LoadError
end

require File.expand_path("../lib/s4", File.dirname(__FILE__))

TestBucket = S4.connect.bucket
NewBucket = ENV["S4_NEW_BUCKET"]

class S4Test < Test::Unit::TestCase
  def fixture(filename="")
    File.join(File.dirname(__FILE__), "fixtures", filename)
  end

  def output(filename="")
    File.join(File.dirname(__FILE__), "output", filename)
  end

  def delete_test_bucket
    `s3cmd del 's3://#{TestBucket}/abc/*' 2>&1`
    `s3cmd del 's3://#{TestBucket}/*' 2>&1`
    `s3cmd rb 's3://#{TestBucket}' 2>&1`
  end
  
  setup do
    FileUtils.rm_rf(output)
    FileUtils.mkdir_p(output)
  end
  
  context "connecting to S3" do
    should "return connected bucket if can connect" do
      s4 = S4.connect
      assert s4
    end
    
    should "bark when no URL is provided" do
      assert_raise(ArgumentError) { S4.connect(url: "") }
      assert_raise(ArgumentError) { S4.connect(url: nil) }
      assert_raise(URI::InvalidURIError) { S4.connect(url: "s3://foo:bar/baz") }
    end
    
    should "raise error if cannot connect" do
      `s3cmd del 's3://#{NewBucket}/*' 2>&1`
      `s3cmd rb 's3://#{NewBucket}' 2>&1`
      
      assert_raise(S4::Error) do
        S4.connect url: ENV["S3_URL"].sub(TestBucket, NewBucket)
      end
    end
  end

  context "when S3 errors occur" do
    # foo is taken bucket, will cause 409 Conflict on create
    should "raise on S3 errors" do
      assert_raise(S4::Error) do
        S4.create url: ENV["S3_URL"].sub(TestBucket, "foo")
      end
    end
  
    should "capture code of S3 error" do
      begin
        S4.create url: ENV["S3_URL"].sub(TestBucket, "foo")
      rescue S4::Error => e
        assert_equal "409", e.status, "Expected 409 got #{e.message}"
      end
    end
  end
  
  context "creating a bucket" do    
    setup do
      `s3cmd del 's3://#{NewBucket}/*' 2>&1`
      `s3cmd rb 's3://#{NewBucket}' 2>&1`
    end
    
    should "create a bucket" do
      assert_equal "ERROR: Bucket '#{NewBucket}' does not exist", `s3cmd ls 's3://#{NewBucket}' 2>&1`.chomp
      
      S4.create url: ENV["S3_URL"].sub(TestBucket, NewBucket)
      
      assert_equal "", `s3cmd ls 's3://#{NewBucket}' 2>&1`.chomp
    end
    
    should "create bucket with public-read ACL" do
      # TODO...
    end
    
    should "raise if bucket creation failed" do
      assert_raise(S4::Error) do
        S4.create url: ENV["S3_URL"].sub(TestBucket, "foo")
      end
    end
    
    should "raise if given invalid ACL" do
      begin
        S4.create url: ENV["S3_URL"], acl: "foo"
      rescue ArgumentError => e
        assert_match /foo/, e.message
      end
    end
  end
  
  context "making a website" do
    setup do
      delete_test_bucket
    end
    
    should "make bucket a website" do
      s4 = S4.create
      
      begin
        open("http://#{s4.website}/")
      rescue OpenURI::HTTPError => e
        assert_match /NoSuchWebsiteConfiguration/, e.io.read
      end
      
      s4.put(StringIO.new("<!DOCTYPE html><html><head><title>Robot Page</title></head><body><h1>Robots!</h1></body></html>", "r"), "index.html", "text/html")
      s4.put(StringIO.new("<!DOCTYPE html><html><head><title>404!</title></head><body><h1>Oh No 404!!!</h1></body></html>", "r"), "404.html", "text/html")
      s4.website!
      
      assert_match /Robots!/, open("http://#{s4.website}/").read
      
      begin
        open("http://#{s4.website}/foo.html")
      rescue OpenURI::HTTPError => e
        raise e unless e.message =~ /404/
        assert_match /Oh No 404!!!/, e.io.read
      end
    end
  end
  
  context "setting policy on a bucket" do
    setup do
      delete_test_bucket
      @s4 = S4.create
    end
    
    should "make all objects public by policy" do
      @s4.upload(fixture("foo.txt"))
      
      begin
        open("http://s3.amazonaws.com/#{TestBucket}/foo.txt")
      rescue OpenURI::HTTPError => e
        assert_match /403 Forbidden/, e.message
      end
      
      @s4.policy = :public_read
      
      assert_equal "abc123", open("http://s3.amazonaws.com/#{TestBucket}/foo.txt").read
    end
  end
  
  context "uploading to bucket" do
    setup do
      delete_test_bucket
      @s4 = S4.create
      @s4.policy = :public_read
    end
    
    should "upload foo.txt" do
      @s4.upload(fixture("foo.txt"))
      
      foo = open("http://s3.amazonaws.com/#{TestBucket}/foo.txt")
      
      assert_equal "abc123", foo.read
      assert_equal "text/plain", foo.content_type      
    end
    
    should "use given content_type" do
      @s4.put StringIO.new("abcdef", "r"), "bar.txt", "text/foobar"
      assert_equal "text/foobar", open("http://s3.amazonaws.com/#{TestBucket}/bar.txt").content_type
    end
    
    should "upload to a path" do
      @s4.put StringIO.new("zoinks!", "r"), "foo/bar.txt", "text/plain"
      assert_equal "zoinks!", open("http://s3.amazonaws.com/#{TestBucket}/foo/bar.txt").read
    end
  end
  
  context "when connected" do
    setup do
      @s4 = S4.connect
    end
        
    should "download foo.txt" do
      `s3cmd put #{fixture("foo.txt")} s3://#{@s4.bucket}/foo.txt`
      @s4.download("foo.txt", output("foo.txt"))

      assert_equal "abc123", File.read(output("foo.txt"))
    end

    should "not download non-existent files" do
      `s3cmd del 's3://#{@s4.bucket}/foo.txt'`
      @s4.download("foo.txt", output("foo.txt"))

      assert !File.exists?(output("foo.txt"))
    end
    
    should "return false when downloading non-existent files" do
      `s3cmd del 's3://#{@s4.bucket}/foo.txt'`
      assert_equal nil, @s4.download("foo.txt", output("foo.txt"))
    end

    should "yield raw response from get of foo.txt" do
      `s3cmd put #{fixture("foo.txt")} s3://#{@s4.bucket}/foo.txt`

      @s4.get("foo.txt") do |response|
        assert_equal "abc123", response.body
      end
    end

    should "delete object" do
      `s3cmd put #{fixture("foo.txt")} s3://#{@s4.bucket}/foo.txt`
      @s4.get("foo.txt") { |response| assert_equal "abc123", response.body }
      @s4.delete("foo.txt")

      assert_equal nil, @s4.get("foo.txt")
    end

    should "return list of items in bucket" do
      `s3cmd del 's3://#{@s4.bucket}/*'`
      `s3cmd del 's3://#{@s4.bucket}/abc/*'`
      
      `s3cmd put #{fixture("foo.txt")} s3://#{@s4.bucket}/foo.txt`
      `s3cmd put #{fixture("foo.txt")} s3://#{@s4.bucket}/bar.txt`
      `s3cmd put #{fixture("foo.txt")} s3://#{@s4.bucket}/baz.txt`

      assert_equal %w( bar.txt baz.txt foo.txt ), @s4.list
    end

    should "return list of keys starting with prefix" do
      `s3cmd put #{fixture("foo.txt")} s3://#{@s4.bucket}/abc/bing.txt`
      `s3cmd put #{fixture("foo.txt")} s3://#{@s4.bucket}/abc/bang.txt`
      `s3cmd put #{fixture("foo.txt")} s3://#{@s4.bucket}/boom.txt`

      assert_equal %w( abc/bang.txt abc/bing.txt ), @s4.list("abc/")
    end

    should "get content with special chars in it" do
      `s3cmd put #{fixture("foo.txt")} 's3://#{@s4.bucket}/foo bar+baz.txt'`

      @s4.get("foo bar+baz.txt") { |response| assert_equal "abc123", response.body }
    end
  end
end
