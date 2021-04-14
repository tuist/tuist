# frozen_string_literal: true

require "rake/testtask"
require "rubygems"
require "cucumber"
require "cucumber/rake/task"
require "mkmf"
require "fileutils"
require "google/cloud/storage"
require "encrypted/environment"
require "colorize"
require "highline"
require "tmpdir"
require "json"
require "zip"
require "macho"

desc("Install git hooks")
task :install_git_hooks do
  system("cp hooks/pre-commit .git/hooks/pre-commit")
  system("chmod u+x .git/hooks/pre-commit")
  puts("pre-commit hook installed on .git/hooks/")
end

desc("Builds and archive a release version of tuist and tuistenv for local testing.")
task :local_package do
  package
end

desc("Builds, archives, and publishes tuist and tuistenv for release")
task :release, [:version] do |_task, options|
  decrypt_secrets
  release(options[:version])
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
  system("swift", "build", "--product", "tuist", "--configuration", "release", "--package-path", File.expand_path("projects/tuist", __dir__))
  system(
    "swift", "build",
    "--product", "ProjectDescription",
    "--configuration", "release",
    "-Xswiftc", "-enable-library-evolution",
    "-Xswiftc", "-emit-module-interface",
    "-Xswiftc", "-emit-module-interface-path",
    "-Xswiftc", ".build/release/ProjectDescription.swiftinterface",
    "--package-path", File.expand_path("projects/tuist", __dir__)
  )
  system("swift", "build", "--product", "tuistenv", "--configuration", "release", "--package-path", File.expand_path("projects/tuist", __dir__))

  build_templates_path = File.join(__dir__, "projects/tuist/.build/release/Templates")
  script_path = File.join(__dir__, "projects/tuist/.build/release/script")
  vendor_path = File.join(__dir__, "projects/tuist/.build/release/vendor")

  FileUtils.rm_rf(build_templates_path) if File.exist?(build_templates_path)
  FileUtils.cp_r(File.expand_path("projects/tuist/Templates", __dir__), build_templates_path)
  FileUtils.rm_rf(script_path) if File.exist?(script_path)
  FileUtils.cp_r(File.expand_path("projects/scripts", __dir__), script_path)
  FileUtils.cp_r(File.expand_path("projects/tuist/vendor", __dir__), vendor_path)

  File.delete("tuist.zip") if File.exist?("tuist.zip")
  File.delete("tuistenv.zip") if File.exist?("tuistenv.zip")

  Dir.chdir(File.expand_path("projects/tuist/.build/release", __dir__)) do
    system(
      "zip", "-q", "-r", "--symlinks",
      "tuist.zip", "tuist",
      "ProjectDescription.swiftmodule",
      "ProjectDescription.swiftdoc",
      "libProjectDescription.dylib",
      "ProjectDescription.swiftinterface",
      "Templates",
      "vendor",
      "script"
    )
    system("zip", "-q", "-r", "--symlinks", "tuistenv.zip", "tuistenv")
  end

  FileUtils.cp(
    File.expand_path("projects/tuist/.build/release/tuist.zip", __dir__), 
    File.expand_path("build/tuist.zip", __dir__)
  )
  FileUtils.cp(
    File.expand_path("projects/tuist/.build/release/tuistenv.zip", __dir__), 
    File.expand_path("build/tuistenv.zip", __dir__)
  )
end

def release(version)
  if version.nil?
    version = cli.ask("Introduce the released version:")
  end

  puts "Releasing #{version} 🚀"

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
