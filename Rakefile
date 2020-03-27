# frozen_string_literal: true

require 'rubygems'
require 'cucumber'
require 'cucumber/rake/task'
require 'mkmf'
require 'fileutils'
require "google/cloud/storage"
require "encrypted/environment"
require 'colorize'
require 'highline'
require 'tmpdir'

Cucumber::Rake::Task.new(:features) do |t|
  t.cucumber_opts = "--format pretty"
end

desc("Formats the code style")
task :style_correct do
  system("swiftformat", ".")
  system("swiftlint", "autocorrect")
end

desc("Swift format check")
task :swift_format do
  Kernel.system("swiftformat", "--lint", ".") || abort
end

desc("Lints the Ruby code style")
task :style_ruby do
  system("bundle", "exec", "rubocop")
end

desc("Corrects the issues with the Ruby style")
task :style_ruby_correct do
  system("bundle", "exec", "rubocop", "-a")
end

desc("Builds, archives, and publishes tuist and tuistenv for release")
task :release do
  decrypt_secrets
  release
end

desc("Publishes the installation scripts")
task :release_scripts do
  decrypt_secrets
  release_scripts
end

desc("Encrypt secret keys")
task :encrypt_secrets do
  Encrypted::Environment.encrypt_ejson("secrets.ejson", private_key: ENV["SECRET_KEY"])
end

def decrypt_secrets
  Encrypted::Environment.load_from_ejson("secrets.ejson", private_key: ENV["SECRET_KEY"])
end

def release_scripts
  bucket = storage.bucket("tuist-releases")
  print_section("Uploading installation scripts to the tuist-releases bucket on GCS")
  bucket.create_file("script/install", "scripts/install").acl.public!
  bucket.create_file("script/uninstall", "scripts/uninstall").acl.public!
end

def package
  print_section("Building tuist")
  FileUtils.mkdir_p("build")
  system("swift", "build", "--product", "tuist", "--configuration", "release")
  system(
    "swift", "build",
    "--product", "ProjectDescription",
    "--configuration", "release",
    "-Xswiftc", "-enable-library-evolution",
    "-Xswiftc", "-emit-module-interface",
    "-Xswiftc", "-emit-module-interface-path",
    "-Xswiftc", ".build/release/ProjectDescription.swiftinterface"
  )
  system("swift", "build", "--product", "tuistenv", "--configuration", "release")
  
  FileUtils.cp_r(File.expand_path("Templates", __dir__), ".build/release/Templates")

  Dir.chdir(".build/release") do
    system(
      "zip", "-q", "-r", "--symlinks",
      "tuist.zip", "tuist",
      "ProjectDescription.swiftmodule", "ProjectDescription.swiftdoc", "libProjectDescription.dylib", "ProjectDescription.swiftinterface",
      "Templates"
    )
    system("zip", "-q", "-r", "--symlinks", "tuistenv.zip", "tuistenv")
  end

  FileUtils.cp(".build/release/tuist.zip", "build/tuist.zip")
  FileUtils.cp(".build/release/tuistenv.zip", "build/tuistenv.zip")
end

def release
  version = cli.ask("Introduce the released version:")

  package

  bucket = storage.bucket("tuist-releases")

  print_section("Uploading to the tuist-releases bucket on GCS")

  bucket.create_file("build/tuist.zip", "#{version}/tuist.zip").acl.public!
  bucket.create_file("build/tuistenv.zip", "#{version}/tuistenv.zip").acl.public!

  bucket.create_file("build/tuist.zip", "latest/tuist.zip").acl.public!
  bucket.create_file("build/tuistenv.zip", "latest/tuistenv.zip").acl.public!
  Dir.mktmpdir do |tmp_dir|
    version_path = File.join(tmp_dir, "version")
    File.write(version_path, version)
    bucket.create_file(version_path, "latest/version").acl.public!
  end
end

def system(*args)
  Kernel.system(*args) || abort
end

def cli
  @cli ||= HighLine.new
end

def storage
  @storage ||= Google::Cloud::Storage.new(
    project_id: ENV["GCS_PROJECT_ID"],
    credentials: {
      type: ENV["GCS_TYPE"],
      project_id: ENV["GCS_PROJECT_ID"],
      private_key_id: ENV["GCS_PRIVATE_KEY_ID"],
      private_key: ENV["GCS_PRIVATE_KEY"],
      client_email: ENV["GCS_CLIENT_EMAIL"],
      client_id: ENV["GCS_CLIENT_ID"],
      auth_uri: ENV["GCS_AUTH_URI"],
      token_uri: ENV["GCS_TOKEN_URI"],
      auth_provider_x509_cert_url: ENV["GCS_AUTH_PROVIDER_X509_CERT_URL"],
      client_x509_cert_url: ENV["GCS_CLIENT_X509_CERT_URL"],
    }
  )
end

def print_section(text)
  puts text.bold.green
end
