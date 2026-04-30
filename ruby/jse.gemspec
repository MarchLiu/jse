require_relative "lib/jse/version"

Gem::Specification.new do |s|
  s.name        = "jse4r"
  s.version     = JSE::VERSION
  s.summary     = "JSON Structural Expression (JSE) runtime for Ruby"
  s.description = "JSE is a JSON-based structural expression specification. " \
                  "It extends JSON from a data carrier into a medium that can " \
                  "express structured intent and computational logic."
  s.authors     = ["Mars Liu"]
  s.email       = "mars.liu@outlook.com"
  s.homepage    = "https://github.com/MarchLiu/jse"
  s.license     = "MIT"

  s.files       = Dir["lib/**/*.rb"]
  s.require_paths = ["lib"]

  s.required_ruby_version = ">= 3.0"
end
