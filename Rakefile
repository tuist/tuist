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
require 'json'

Cucumber::Rake::Task.new(:features) do |t|
  t.cucumber_opts = "--format pretty"
end

desc("Formats the code style")
task :style_correct do
  system(swiftlint_path, "autocorrect")
  system(swiftformat_path, ".")
end

desc("Swift format check")
task :swift_format do
  Kernel.system(swiftformat_path, "--lint", ".") || abort
end

desc("Swift lint check")
task :swift_lint do
  Kernel.system(swiftlint_path) || abort
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

desc("Packages tuist, tags it with the commit sha and uploads it to gcs")
task :package_commit do
  decrypt_secrets
  package

  bucket = storage.bucket("tuist-builds")

  sha = %x(git rev-parse HEAD).strip.chomp
  print_section("Uploading tuist-#{sha}")
  file = bucket.create_file(
    "build/tuist.zip",
    "#{sha}.zip"
  )

  file.acl.public!
  print_section("Uploaded 🚀")
end

desc("Encrypt secret keys")
task :encrypt_secrets do
  Encrypted::Environment.encrypt_ejson("secrets.ejson", private_key: ENV["SECRET_KEY"])
end

desc("Benchmarks tuist against a specified versiom")
task :benchmark do

  print_section("🛠 Building supporting tools")

  # Build tuistbench
  system(
    "swift", "build", 
    "-c", "release", 
    "--package-path", "tools/tuistbench"
  )

  # Build fixturegen
  system(
    "swift", "build", 
    "-c", "release", 
    "--package-path", "tools/fixturegen"
  )

  # Generate large fixture
  print_section("📁 Generating fixtures ...")
  FileUtils.mkdir_p("generated_fixtures")

  system(
    "tools/fixturegen/.build/release/fixturegen",
    "--path", "generated_fixtures/50_projects",
    "--projects", "50",
  )

  system(
    "tools/fixturegen/.build/release/fixturegen",
    "--path", "generated_fixtures/2000_sources",
    "--projects", "2",
    "--sources", "2000",
  )

  # Generate fixture list
  fixtures = {
    "paths" => [
      "generated_fixtures/50_projects",
      "generated_fixtures/2000_sources",
      "fixtures/ios_app_with_static_frameworks",
      "fixtures/ios_app_with_framework_and_resources",
      "fixtures/ios_app_with_transitive_framework",
      "fixtures/ios_app_with_xcframeworks",
    ]
  }
  File.open(".fixtures.generated.json","w") do |f|
    f.write(fixtures.to_json)
  end

  # Build current version of tuist
  print_section("🔨 Building release version of tuist ...")
  system("swift", "build", "--product", "tuist", "--configuration", "release")
  system("swift", "build", "--product", "tuistenv", "--configuration", "release")
  system("swift", "build", "--product", "ProjectDescription", "--configuration", "release")

  # Download latest tuist
  print_section("⬇️ Downloading latest published version of tuist ...")

  system(".build/release/tuistenv", "update")
  puts("Reference tuist version:")
  system(".build/release/tuistenv", "version")

  print_section("⏱ Benchmarking ...")
  system(
    "tools/tuistbench/.build/release/tuistbench", 
    "-b", ".build/release/tuist",
    "-r", ".build/release/tuistenv",
    "-l", ".fixtures.generated.json",
    "--format", "markdown"
  )

end

def swiftformat_path
  File.expand_path("bin/swiftformat", __dir__)
end

def swiftlint_path
  File.expand_path("bin/swiftlint", __dir__)
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
  
  build_templates_path = File.join(__dir__, ".build/release/Templates")
  FileUtils.rm_rf(build_templates_path) if File.exist?(build_templates_path)
  FileUtils.cp_r(File.expand_path("Templates", __dir__), build_templates_path)

  File.delete("tuist.zip") if File.exist?("tuist.zip")
  File.delete("tuistenv.zip") if File.exist?("tuistenv.zip")

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
  puts(text.bold.green)
end
