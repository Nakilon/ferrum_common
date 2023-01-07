Gem::Specification.new do |spec|
  spec.name         = "ferrum_common"
  spec.version      = "0.0.0"
  spec.summary      = "[WIP] common useful extensions for ferrum or cuprite"

  spec.author       = "Victor Maslov aka Nakilon"
  spec.email        = "nakilon@gmail.com"
  spec.license      = "MIT"
  spec.metadata     = {"source_code_uri" => "https://github.com/nakilon/ferrum_common"}

  spec.add_dependency "ferrum"
  spec.required_ruby_version = ">=2.5"

  spec.files        = %w{ LICENSE ferrum_common.gemspec lib/ferrum_common.rb }
end
