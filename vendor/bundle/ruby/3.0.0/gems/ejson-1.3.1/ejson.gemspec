# coding: utf-8
require File.expand_path('../lib/ejson/version', __FILE__)

files = File.read("MANIFEST").lines.map(&:chomp)

Gem::Specification.new do |spec|
  spec.name          = "ejson"
  spec.version       = EJSON::VERSION
  spec.authors       = ["Shopify"]
  spec.email         = ["admins@shopify.com"]
  spec.summary       = %q{Asymmetric keywise encryption for JSON}
  spec.description   = %q{Secret management by encrypting values in a JSON hash with a public/private keypair}
  spec.homepage      = "https://github.com/Shopify/ejson"
  spec.license       = "MIT"

  spec.files         = files
  spec.executables   = ["ejson"]
  spec.test_files    = []
  spec.require_paths = ["lib"]
end
