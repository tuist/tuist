# frozen_string_literal: true

require 'rubygems'
require 'cucumber'
require 'cucumber/rake/task'
require 'mkmf'
require 'fileutils'
require "google/cloud/storage"
require "encrypted/environment"
require 'colorize'

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

desc("Generates the project Xcode project")
task :generate do
  system("swift", "package", "generate-xcodeproj", "--xcconfig-overrides", "tuist.xcconfig")
end

desc("Packages tuist, tags it with the commit sha and uploads it to gcs")
task :package_commit do
  decrypt_secrets
  package

  bucket = storage.bucket("tuist-builds")

  sha = %x(git rev-parse --short HEAD).strip.chomp
  print_section("Uploading tuist-#{sha}")
  file = bucket.create_file(
    "build/tuist.zip",
    "tuist-#{sha}.zip"
  )

  file.acl.public!
  print_section("Uploaded 🚀")
end

desc("Encrypt secret keys")
task :encrypt_secrets do
  Encrypted::Environment.encrypt_ejson("secrets.ejson", private_key: ENV["SECRET_KEY"])
end

def decrypt_secrets
  Encrypted::Environment.load_from_ejson("secrets.ejson", private_key: ENV["SECRET_KEY"])
end

def package
  with_sentry_dsn do
    print_section("Building tuist")
    FileUtils.mkdir_p("build")

    link_args = [
      "-Xswiftc", "-F", "-Xswiftc", File.expand_path("./Frameworks", __dir__),
      "-Xswiftc", "-framework", "-Xswiftc", "Sentry"
    ]
    build_cli_args = ["swift", "build", "--configuration", "release"]

    build_tuist_args = build_cli_args.dup
    build_tuist_args.concat(["--product", "tuist"])
    build_tuist_args.concat(link_args)

    build_tuistenv_args = build_cli_args.dup
    build_tuistenv_args.concat(["--product", "tuistenv"])
    build_tuistenv_args.concat(link_args)

    # ProjectDescription
    system("swift", "build", "--product", "ProjectDescription", "--configuration", "release")

    # Tuist
    system(*build_tuist_args)
    system("install_name_tool", "-add_rpath", "@executable_path", ".build/release/tuist")

    # Tuistenv
    system(*build_tuistenv_args)
    system("install_name_tool", "-add_rpath", "@executable_path", ".build/release/tuistenv")
    system("install_name_tool", "-add_rpath", "/usr/local/etc", ".build/release/tuistenv")

    Dir.chdir(".build/release") do
      system("zip", "-q", "-r", "--symlinks", "tuist.zip", "tuist", "ProjectDescription.swiftmodule", "ProjectDescription.swiftdoc", " libProjectDescription.dylib")
      system("zip", "-q", "-r", "--symlinks", "tuistenv.zip", "tuistenv")
    end

    Dir.chdir("Frameworks") do
      system("zip", "-q", "-r", "--symlinks", "Sentry.framework.zip", "Sentry.framework")
    end

    FileUtils.cp(".build/release/tuist.zip", "build/tuist.zip")
    FileUtils.cp(".build/release/tuistenv.zip", "build/tuistenv.zip")
    FileUtils.cp("Frameworks/Sentry.framework.zip", "build/Sentry.framework.zip")
  end
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

def with_sentry_dsn
  path = File.join(__dir__, "Sources/TuistCore/Errors/SentryDsn.swift")
  default_content = File.read(path)
  dsn = ENV.fetch('SENTRY_DSN')
  File.write(path, "var sentryDsn: String = \"#{dsn}\"")
  yield
ensure
  File.write(path, default_content)
end

def print_section(text)
  puts text.bold.green
end
