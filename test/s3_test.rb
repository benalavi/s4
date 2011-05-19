require "cutest"
require "timecop"
require "fileutils"

begin
  require "ruby-debug"
rescue LoadError
end

require File.expand_path("../lib/s3", File.dirname(__FILE__))

def fixture(filename="")
  File.join(File.dirname(__FILE__), "fixtures", filename)
end

def output(filename="")
  File.join(File.dirname(__FILE__), "output", filename)
end

# S3 errors are defined dynamically -- have to make them explicit for testing
class S3::NoSuchKey < S3::Error;end;

Bucket = URI(ENV["S3_URL"]).path[1..-1]

scope do
  setup do
    FileUtils.rm_rf(output)
    FileUtils.mkdir_p(output)
    @s3 = S3.new
  end

  test "should download foo.txt" do
    `s3cmd put #{fixture("foo.txt")} s3://#{Bucket}/foo.txt`
    @s3.download("foo.txt", output("foo.txt"))

    assert_equal "abc123", File.read(output("foo.txt"))
  end

  test "should yield raw response from get of foo.txt" do
    `s3cmd put #{fixture("foo.txt")} s3://#{Bucket}/foo.txt`

    @s3.get("foo.txt") do |response|
      assert_equal "abc123", response.body
    end
  end

  test "should delete object" do
    `s3cmd put #{fixture("foo.txt")} s3://#{Bucket}/foo.txt`
    @s3.get("foo.txt") { |response| assert_equal "abc123", response.body }
    @s3.delete("foo.txt")

    assert_raise(S3::NoSuchKey) { @s3.download("foo.txt", output("foo.txt")) }
  end

  test "should return list of items in bucket" do
    `s3cmd del 's3://#{Bucket}/abc/*'`
    `s3cmd del 's3://#{Bucket}/boom.txt'`
    `s3cmd del 's3://#{Bucket}/foo\ bar+baz.txt'`
    `s3cmd put #{fixture("foo.txt")} s3://#{Bucket}/foo.txt`
    `s3cmd put #{fixture("foo.txt")} s3://#{Bucket}/bar.txt`
    `s3cmd put #{fixture("foo.txt")} s3://#{Bucket}/baz.txt`

    assert_equal %w( bar.txt baz.txt foo.txt ), @s3.list
  end

  test "should return list of keys starting with prefix" do
    `s3cmd put #{fixture("foo.txt")} s3://#{Bucket}/abc/bing.txt`
    `s3cmd put #{fixture("foo.txt")} s3://#{Bucket}/abc/bang.txt`
    `s3cmd put #{fixture("foo.txt")} s3://#{Bucket}/boom.txt`

    assert_equal %w( abc/bang.txt abc/bing.txt ), @s3.list("abc/")
  end

  test "should get content with special chars in it" do
    `s3cmd put #{fixture("foo.txt")} 's3://#{Bucket}/foo bar+baz.txt'`

    @s3.get("foo bar+baz.txt") { |response| assert_equal "abc123", response.body }
  end

  test "should upload foo.txt" do
    `s3cmd del 's3://#{Bucket}/foo.txt'`

    s3 = S3.new

    s3.upload(fixture("foo.txt"))

    s3.get("foo.txt") { |response| assert_equal "abc123", response.body }
  end
end
