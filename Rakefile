# frozen_string_literal: true

SWIFTDOC_VERSION = "1.0.0-beta.5"
SWIFTLINT_VERSION = "0.40.2"
XCBEAUTIFY_VERSION = "0.8.1"

require 'rake/testtask'
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
require 'zip'
require 'macho'

desc("Runs the Fourier tests")
Rake::TestTask.new do |t|
  t.name = "test_fourier"
  t.libs += [File.expand_path('./tools/fourier/test', __dir__)]
  test_root = File.expand_path('./tools/fourier/test', __dir__)
  t.test_files = FileList[File.join(test_root, '**', '*_test.rb')]
  t.verbose = false
  t.warning = false
end

desc("Updates swift-doc binary with the latest version available.")
task :swift_doc_update do
  root_dir = File.expand_path(__dir__)
  Dir.mktmpdir do |temporary_dir|
    Dir.chdir(temporary_dir) do
      system("curl", "-LO", "https://github.com/SwiftDocOrg/swift-doc/archive/#{SWIFTDOC_VERSION}.zip")
      extract_zip("#{SWIFTDOC_VERSION}.zip", "swift-doc")
      Dir.chdir("swift-doc/swift-doc-#{SWIFTDOC_VERSION}") do
        system("make", "swift-doc")
      end
      release_dir = File.join(temporary_dir, "swift-doc/swift-doc-#{SWIFTDOC_VERSION}/.build/release/")
      vendor_dir = File.join(root_dir, "vendor")
      dst_binary_path = File.join(vendor_dir, "swift-doc")
      bundle_paths = Dir[File.join(release_dir, "*.bundle")]

      # Copy binary and bundles
      binary_path = File.join(release_dir, "swift-doc")
      File.delete(dst_binary_path) if File.exist?(dst_binary_path)
      FileUtils.cp(binary_path, dst_binary_path)
      bundle_paths.each do |bundle_path|
        bundle_dst_path = File.join(vendor_dir, File.basename(bundle_path))
        FileUtils.rm_rf(bundle_dst_path) if File.exist?(bundle_dst_path)
        FileUtils.cp_r(bundle_path, bundle_dst_path)
      end

      # Change the reference to lib_InternalSwiftSyntaxParser.dylib
      # https://github.com/SwiftDocOrg/homebrew-formulae/blob/master/Formula/swift-doc.rb#L43
      macho = MachO.open(dst_binary_path)
      break unless (toolchain = macho.rpaths.find { |path| path.include?(".xctoolchain") })
      syntax_parser_dylib_name = "lib_InternalSwiftSyntaxParser.dylib"
      FileUtils.cp(File.join(toolchain, syntax_parser_dylib_name), File.join(vendor_dir, syntax_parser_dylib_name))

      # Write version
      File.write(File.join(root_dir, "vendor/.swiftdoc.version"), SWIFTDOC_VERSION)
    end
  end
end

desc("Updates swift-lint binary with the latest version available.")
task :swift_lint_update do
  root_dir = File.expand_path(__dir__)
  Dir.mktmpdir do |temporary_dir|
    Dir.chdir(temporary_dir) do
      system("curl", "-LO",
"https://github.com/realm/SwiftLint/releases/download/#{SWIFTLINT_VERSION}/portable_swiftlint.zip")
      extract_zip("portable_swiftlint.zip", "portable_swiftlint")
      system("cp", "portable_swiftlint/swiftlint", "#{root_dir}/vendor/swiftlint")
    end
  end
  File.write(File.join(root_dir, "vendor/.swiftlint.version"), SWIFTLINT_VERSION)
end

desc("Install git hooks")
task :install_git_hooks do
  system("cp hooks/pre-commit .git/hooks/pre-commit")
  system("chmod u+x .git/hooks/pre-commit")
  puts("pre-commit hook installed on .git/hooks/")
end

desc("Updates xcbeautify binary with the latest version available.")
task :xcbeautify_update do
  root_dir = File.expand_path(__dir__)
  Dir.mktmpdir do |temporary_dir|
    Dir.chdir(temporary_dir) do
      system("curl", "-LO", "https://github.com/thii/xcbeautify/archive/#{XCBEAUTIFY_VERSION}.zip")
      extract_zip("#{XCBEAUTIFY_VERSION}.zip", "xcbeautify")
      Dir.chdir("xcbeautify/xcbeautify-#{XCBEAUTIFY_VERSION}") do
        system("make", "build")
      end
      release_dir = File.join(temporary_dir,
"xcbeautify/xcbeautify-#{XCBEAUTIFY_VERSION}/.build/release")
      vendor_dir = File.join(root_dir, "vendor")
      dst_binary_path = File.join(vendor_dir, "xcbeautify")

      # Copy binary
      binary_path = File.join(release_dir, "xcbeautify")
      File.delete(dst_binary_path) if File.exist?(dst_binary_path)
      FileUtils.cp(binary_path, dst_binary_path)
    end
  end
  # Write version
  File.write(File.join(root_dir, "vendor/.xcbeautify.version"), XCBEAUTIFY_VERSION)
end

desc("Formats the code style")
task :style_correct do
  system(code_style_path)
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
    ],
  }
  File.open(".fixtures.generated.json", "w") do |f|
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

def code_style_path
  File.expand_path("script/code_style.sh", __dir__)
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
  vendor_path = File.join(__dir__, ".build/release/vendor")

  FileUtils.rm_rf(build_templates_path) if File.exist?(build_templates_path)
  FileUtils.cp_r(File.expand_path("Templates", __dir__), build_templates_path)
  FileUtils.cp_r(File.expand_path("vendor", __dir__), vendor_path)

  File.delete("tuist.zip") if File.exist?("tuist.zip")
  File.delete("tuistenv.zip") if File.exist?("tuistenv.zip")

  Dir.chdir(".build/release") do
    system(
      "zip", "-q", "-r", "--symlinks",
      "tuist.zip", "tuist",
      "ProjectDescription.swiftmodule",
      "ProjectDescription.swiftdoc",
      "libProjectDescription.dylib",
      "ProjectDescription.swiftinterface",
      "Templates",
      "vendor"
    )
    system("zip", "-q", "-r", "--symlinks", "tuistenv.zip", "tuistenv")
  end

  FileUtils.cp(".build/release/tuist.zip", "build/tuist.zip")
  FileUtils.cp(".build/release/tuistenv.zip", "build/tuistenv.zip")
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

def extract_zip(file, destination)
  FileUtils.mkdir_p(destination)

  Zip::File.open(file) do |zip_file|
    zip_file.each do |f|
      fpath = File.join(destination, f.name)
      zip_file.extract(f, fpath) unless File.exist?(fpath)
    end
  end
end
