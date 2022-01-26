# -*- encoding: utf-8 -*-
# stub: protobuf-cucumber 3.10.8 ruby lib

Gem::Specification.new do |s|
  s.name = "protobuf-cucumber".freeze
  s.version = "3.10.8"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["BJ Neilsen".freeze, "Brandon Dewitt".freeze, "Devin Christensen".freeze, "Adam Hutchison".freeze]
  s.date = "2020-02-05"
  s.description = "Google Protocol Buffers serialization and RPC implementation for Ruby.".freeze
  s.email = ["bj.neilsen+protobuf@gmail.com".freeze, "brandonsdewitt+protobuf@gmail.com".freeze, "quixoten@gmail.com".freeze, "liveh2o@gmail.com".freeze]
  s.executables = ["protoc-gen-ruby".freeze, "rpc_server".freeze]
  s.files = ["bin/protoc-gen-ruby".freeze, "bin/rpc_server".freeze]
  s.homepage = "https://github.com/localshred/protobuf".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.2.32".freeze
  s.summary = "Google Protocol Buffers serialization and RPC implementation for Ruby.".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<activesupport>.freeze, [">= 3.2"])
    s.add_runtime_dependency(%q<middleware>.freeze, [">= 0"])
    s.add_runtime_dependency(%q<thor>.freeze, [">= 0"])
    s.add_runtime_dependency(%q<thread_safe>.freeze, [">= 0"])
    s.add_development_dependency(%q<benchmark-ips>.freeze, [">= 0"])
    s.add_development_dependency(%q<ffi-rzmq>.freeze, [">= 0"])
    s.add_development_dependency(%q<rake>.freeze, ["< 11.0"])
    s.add_development_dependency(%q<rspec>.freeze, [">= 3.0"])
    s.add_development_dependency(%q<rubocop>.freeze, ["~> 0.38.0"])
    s.add_development_dependency(%q<parser>.freeze, ["= 2.3.0.6"])
    s.add_development_dependency(%q<simplecov>.freeze, [">= 0"])
    s.add_development_dependency(%q<timecop>.freeze, [">= 0"])
    s.add_development_dependency(%q<yard>.freeze, [">= 0"])
    s.add_development_dependency(%q<pry-byebug>.freeze, [">= 0"])
    s.add_development_dependency(%q<pry-stack_explorer>.freeze, [">= 0"])
    s.add_development_dependency(%q<varint>.freeze, [">= 0"])
    s.add_development_dependency(%q<ruby-prof>.freeze, [">= 0"])
  else
    s.add_dependency(%q<activesupport>.freeze, [">= 3.2"])
    s.add_dependency(%q<middleware>.freeze, [">= 0"])
    s.add_dependency(%q<thor>.freeze, [">= 0"])
    s.add_dependency(%q<thread_safe>.freeze, [">= 0"])
    s.add_dependency(%q<benchmark-ips>.freeze, [">= 0"])
    s.add_dependency(%q<ffi-rzmq>.freeze, [">= 0"])
    s.add_dependency(%q<rake>.freeze, ["< 11.0"])
    s.add_dependency(%q<rspec>.freeze, [">= 3.0"])
    s.add_dependency(%q<rubocop>.freeze, ["~> 0.38.0"])
    s.add_dependency(%q<parser>.freeze, ["= 2.3.0.6"])
    s.add_dependency(%q<simplecov>.freeze, [">= 0"])
    s.add_dependency(%q<timecop>.freeze, [">= 0"])
    s.add_dependency(%q<yard>.freeze, [">= 0"])
    s.add_dependency(%q<pry-byebug>.freeze, [">= 0"])
    s.add_dependency(%q<pry-stack_explorer>.freeze, [">= 0"])
    s.add_dependency(%q<varint>.freeze, [">= 0"])
    s.add_dependency(%q<ruby-prof>.freeze, [">= 0"])
  end
end
