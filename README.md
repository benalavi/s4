S4
==

A Simpler API for Amazon Web Services S3.

It does not implement the full S3 API, nor is that the intention. It just does
the basics (managing files in a bucket) in a very simple way with a very small
code footprint.

Usage
-----

    $assets = S4.new("s3://0PN5J17HBGZHT7JJ3X82:k3nL7gH3+PadhTEVn5EXAMPLE@s3.amazonaws.com/assets.mysite.com")

    $assets.upload("puppy.jpg", "animals/puppy.jpg")
    $assets.upload("penguin.jpg", "animals/penguin.jpg")
    
    $assets.list("animals/") #=> [ "animals/puppy.jpg", "animals/penguin.jpg" ]
    
    $assets.download("animals/penguin.jpg", "penguin.jpg")
    
    $assets.delete("animals/penguin.jpg")

Low-level access
    
    $assets.get("animals/gigantic_penguin_movie.mp4") do |response|
      File.open("gigantic_penguin_movie.mp4", "wb") do |io|
        response.read_body do |chunk|
          io.write(chunk)
          puts "."
        end
      end
    end    

Acknowledgements
----------------

Michel Martens & Chris Schneider for input on the original design + see
committers for more.

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
