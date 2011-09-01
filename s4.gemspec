require "./lib/s4"

Gem::Specification.new do |s|
  s.name = "s4"
  s.version = S4::VERSION
  s.summary = "Simple API for AWS S3"
  s.description = "Simple API for AWS S3"
  s.authors = ["Ben Alavi"]
  s.email = ["ben.alavi@citrusbyte.com"]
  s.homepage = "http://github.com/benalavi/s4"

  s.files = Dir[
    "LICENSE",
    "README.markdown",
    "Rakefile",
    "lib/**/*.rb",
    "*.gemspec",
    "test/**/*.rb"
  ]

  s.add_dependency "net-http-persistent", "~> 1.7"

  s.add_development_dependency "cutest"
  s.add_development_dependency "timecop", "~> 0.3"
end
