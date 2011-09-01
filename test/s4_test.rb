require "contest"
require "timecop"
require "fileutils"

begin
  require "ruby-debug"
rescue LoadError
end

require File.expand_path("../lib/s4", File.dirname(__FILE__))

def fixture(filename="")
  File.join(File.dirname(__FILE__), "fixtures", filename)
end

def output(filename="")
  File.join(File.dirname(__FILE__), "output", filename)
end

NewBucket = "s4-bucketthatdoesntexist"
TestBucket = "s4-test-bucket"

class S4Test < Test::Unit::TestCase
  setup do
    FileUtils.rm_rf(output)
    FileUtils.mkdir_p(output)
  end
  
  context "connecting to S3" do
    should "return connected bucket if can connect" do
      s4 = S4.connect
    end
    
    should "raise error if cannot connect" do
      `s3cmd rb 's3://#{NewBucket}' 2>&1`
      
      assert_raise(S4::Error) do
        S4.connect ENV["S3_URL"].sub(TestBucket, NewBucket)
      end
    end
  end

  context "when S3 errors occur" do
    # foo is taken bucket, will cause 409 Conflict on create
    
    should "raise on S3 errors" do
      assert_raise(S4::Error) do
        S4.create(ENV["S3_URL"].sub(TestBucket, "foo"))
      end
    end
  
    should "capture code of S3 error" do
      begin
        S4.create(ENV["S3_URL"].sub(TestBucket, "foo"))
      rescue S4::Error => e
        assert_equal "409", e.status
      end
    end
  end
  
  context "creating a bucket" do    
    setup do
      `s3cmd rb 's3://#{NewBucket}' 2>&1`
    end
    
    should "create a bucket" do
      assert_equal "ERROR: Bucket '#{NewBucket}' does not exist", `s3cmd ls 's3://#{NewBucket}' 2>&1`.chomp
      s4 = S4.create ENV["S3_URL"].sub(TestBucket, NewBucket)
      assert_equal "", `s3cmd ls 's3://#{NewBucket}' 2>&1`.chomp
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
      `s3cmd del 's3://#{@s4.bucket}/abc/*'`
      `s3cmd del 's3://#{@s4.bucket}/boom.txt'`
      `s3cmd del 's3://#{@s4.bucket}/foo\ bar+baz.txt'`
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

    should "upload foo.txt" do
      `s3cmd del 's3://#{@s4.bucket}/foo.txt'`
      @s4.upload(fixture("foo.txt"))
      @s4.get("foo.txt") { |response| assert_equal "abc123", response.body }
    end

    should "bark when no URL is provided" do
      assert_raise(ArgumentError) { S4.connect("") }
      assert_raise(ArgumentError) { S4.connect(nil) }

      assert_raise(URI::InvalidURIError) { S4.connect("s3://foo:bar/baz") }
    end
  end
end
