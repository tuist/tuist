# frozen_string_literal: true

require 'rubygems'
require 'cucumber'
require 'cucumber/rake/task'
require 'mkmf'
require 'fileutils'
require "google/cloud/storage"
require "encrypted/environment"

Cucumber::Rake::Task.new(:features) do |t|
  t.cucumber_opts = "--format pretty"
end

desc("Formats the code style")
task :style_correct do
  system("swiftformat", ".")
  system("swiftlint", "autocorrect")
end

desc("Lints the Ruby code style")
task :style_ruby do
  system("bundle", "exec", "rubocop")
end

desc("Corrects the issues with the Ruby style")
task :style_ruby_correct do
  system("bundle", "exec", "rubocop", "-a")
end

desc("Builds tuist and tuistenv for release and archives them")
task :package do
  decrypt_secrets
  package
end

desc("Packages tuist, tags it with the commit sha and uploads it to gcs")
task :package_commit do
  decrypt_secrets
  package
  
  bucket = storage.bucket("tuist-builds")

  sha = %x(git show --pretty=%H).strip
  file = bucket.create_file(
    "build/tuist.zip",
    "tuist-#{sha}.zip"
  )

  file.acl.public!
end

desc("Encrypt secret keys")
task :encrypt_secrets do
  Encrypted::Environment.encrypt_ejson("secrets.ejson", private_key: ENV["SECRET_KEY"])
end

def decrypt_secrets
  Encrypted::Environment.load_from_ejson("secrets.ejson", private_key: ENV["SECRET_KEY"])
end

def package
  FileUtils.mkdir_p("build")
  system("swift", "build", "--product", "tuist", "--configuration", "release")
  system("swift", "build", "--product", "ProjectDescription", "--configuration", "release")
  system("swift", "build", "--product", "tuistenv", "--configuration", "release")

  Dir.chdir(".build/release") do
    system("zip", "-q", "-r", "--symlinks", "tuist.zip", "tuist", "ProjectDescription.swiftmodule", "ProjectDescription.swiftdoc", " libProjectDescription.dylib")
    system("zip", "-q", "-r", "--symlinks", "tuistenv.zip", "tuistenv")
  end

  FileUtils.cp(".build/release/tuist.zip", "build/tuist.zip")
  FileUtils.cp(".build/release/tuistenv.zip", "build/tuistenv.zip")
end

def system(*args)
  Kernel.system(*args) || abort
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
