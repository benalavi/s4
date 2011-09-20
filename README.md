S4
==

A Simpler API for Amazon Web Services S3.

It does not implement the full S3 API, nor is that the intention. It just does
the basics (managing files in a bucket) in a very simple way with a
<del>very</del> small code footprint.

Usage
-----

    $assets = S4.connect url: "s3://0PN5J17HBGZHT7JJ3X82:k3nL7gH3+PadhTEVn5EXAMPLE@s3.amazonaws.com/assets.mysite.com"

    $assets.upload "puppy.jpg", "animals/puppy.jpg"
    $assets.upload "penguin.jpg", "animals/penguin.jpg"
    $assets.list "animals/" #=> [ "animals/puppy.jpg", "animals/penguin.jpg" ]

    $assets.download "animals/penguin.jpg", "penguin.jpg"

    $assets.delete "animals/penguin.jpg"
    $assets.list "animals/" #=> [ "animals/puppy.jpg" ]

    $assets.upload "ufo.jpg"
    $assets.list #=> [ "ufo.jpg", "animals/puppy.jpg" ]

Without a URL given, S4 will attempt to read one from ENV["S3_URL"]:

    $ export S3_URL="s3://0PN5J17HBGZHT7JJ3X82:k3nL7gH3+PadhTEVn5EXAMPLE@s3.amazonaws.com/assets.mysite.com"
    ...
    $assets = S4.connect

Handy snippet for multiple buckets w/ the same account:

    $ export S3_URL="s3://0PN5J17HBGZHT7JJ3X82:k3nL7gH3+PadhTEVn5EXAMPLE@s3.amazonaws.com/%s"
    ...
    $assets = S4.connect url: ENV["S3_URL"] % "assets"
    $videos = S4.connect url: ENV["S3_URL"] % "videos"

Low-level access:

    $assets.get "animals/gigantic_penguin_movie.mp4" do |response|
      File.open "gigantic_penguin_movie.mp4", "wb" do |io|
        response.read_body do |chunk|
          io.write chunk
          puts "."
        end
      end
    end

    $assets.put StringIO.new("My Novel -- By Ben Alavi...", "r"), "novel.txt", "text/plain"

Create a bucket (returns the bucket if it already exists and is accessible):

    $musics = S4.create url: "s3://0PN5J17HBGZHT7JJ3X82:k3nL7gH3+PadhTEVn5EXAMPLE@s3.amazonaws.com/musics.mysite.com"

Make a bucket into a static website:

    $site = S4.connect url: "s3://0PN5J17HBGZHT7JJ3X82:k3nL7gH3+PadhTEVn5EXAMPLE@s3.amazonaws.com/website.mysite.com"
    $site.website!
    $site.put StringIO.new("<!DOCTYPE html><html><head><title>My Website</title></head><body><h1><blink><font color="yellow">HELLO! WELCOME TO MY WEBSITE</font></blink></h1></body></html>", "r"), "index.html", "text/html"
    Net::HTTP.get "http://#{$site.website}/" #=> ...HELLO! WELCOME TO MY WEBSITE...

Plus a handful of other miscellaneous things (see [RDoc](http://rubydoc.info/gems/s4))...

Acknowledgements
----------------

* Michel Martens
* Chris Schneider
* Damian Janowski
* Cyril David

License
-------

Copyright (c) 2011 Ben Alavi

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.
