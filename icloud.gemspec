# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'icloud/version'

Gem::Specification.new do |gem|
  gem.name          = "icloud"
  gem.version       = Icloud::VERSION
  gem.authors       = ["Maxim"]
  gem.email         = ["parallel588@gmail.com"]
  gem.description   = %q{Non official iCloud API}
  gem.summary       = %q{Non official iCloud API}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency "faraday", "~> 0.8.4"
  gem.add_dependency "uuid", "~> 2.3.6"
  gem.add_dependency "oj", "~> 2.0.0"

end
