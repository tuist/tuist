# frozen_string_literal: true

require 'semantic'
require 'octokit'
require 'date'
require 'dotenv/load'

REPOSITORY = 'xcode-project-manager/xpm'
BUILD_PATH = 'build'
APP_NAME = 'xpm'
GITHUB_TOKEN = ENV['GH_TOKEN']
APPCAST_PATH = 'appcast.xml'
CHANGELOG_PATH = 'CHANGELOG.md'
WORKSPACE_PATH = "App.xcworkspace"

def execute(command)
  sh(command)
end

def format
  execute('swiftformat .')
end

def build(config = 'Debug')
  abort('SENTRY_DSN variable missing') unless ENV['SENTRY_DSN']
  abort('SENTRY_AUTH_TOKEN variable missing') unless ENV['SENTRY_AUTH_TOKEN']
  execute('swift package generate-xcodeproj')
  env_vars = "SENTR_DSN=#{ENV['SENTR_DSN']} SENTRY_AUTH_TOKEN=#{ENV['SENTRY_AUTH_TOKEN']}"
  execute("#{env_vars} xcodebuild -workspace #{WORKSPACE_PATH} -scheme xpm -configuration #{config} build")
end

def test
  execute('swift package generate-xcodeproj')
  execute("xcodebuild -workspace #{WORKSPACE_PATH} -scheme xpm-Package -config Debug test -enableCodeCoverage YES")
  execute("xcodebuild -workspace #{WORKSPACE_PATH} -scheme xpmKit test CODE_SIGN_IDENTITY=''")
end

def decrypt_keys
  execute('openssl aes-256-cbc -k "$ENCRYPTION_SECRET" -in certs/xpm_Dist.provisionprofile.enc -d -a -out certs/xpm_Dist.provisionprofile')
  execute('openssl aes-256-cbc -k "$ENCRYPTION_SECRET" -in certs/dist.cer.enc -d -a -out certs/dist.cer')
  execute('openssl aes-256-cbc -k "$ENCRYPTION_SECRET" -in certs/dist.p12.enc -d -a -out certs/dist.p12')
  execute('openssl aes-256-cbc -k "$ENCRYPTION_SECRET" -in keys/dsa_priv.pem.enc -d -a -out keys/dsa_priv.pem')
end

def install_keys
  execute('./scripts/add-key.sh')
end

def archive_and_export
  execute("xcodebuild -workspace #{WORKSPACE_PATH} -scheme xpm -config Release -archivePath ./#{BUILD_PATH}/archive clean archive")
  execute("xcodebuild -archivePath ./#{BUILD_PATH}/archive.xcarchive -exportArchive -exportPath #{BUILD_PATH} -exportOptionsPlist exportOptions.plist")
end

def bump_version
  info_plist_path = 'App/Info.plist'
  new_bundle_version = `/usr/libexec/PlistBuddy -c \"Print CFBundleVersion\" #{info_plist_path}`.strip.to_i + 1
  current_version = Semantic::Version.new(`/usr/libexec/PlistBuddy -c \"Print CFBundleShortVersionString\" #{info_plist_path}`.strip)
  new_version = current_version.increment!(:minor).to_s
  current_version = current_version.to_s
  puts("Bumping version to #{new_version}(#{new_bundle_version})")
  execute("/usr/libexec/PlistBuddy -c \"Set :CFBundleVersion #{new_bundle_version}\" \"#{info_plist_path}\"")
  execute("/usr/libexec/PlistBuddy -c \"Set :CFBundleShortVersionString #{new_version}\" \"#{info_plist_path}\"")
  [new_bundle_version, new_version]
end

def decrypt_and_install_keys
  puts 'Decrypting and installing keys'
  decrypt_keys
  install_keys
end

def changelog(version)
  version = Semantic::Version.new(version)
  version_regex = /##\s+#{version.major}\.#{version.minor}\.#{version.patch}/
  any_version_regex = /##\s+\d+\.\d+\.\d+/
  output = ''
  reading = false
  File.readlines(CHANGELOG_PATH).each do |line|
    if line =~ version_regex && !reading
      reading = true
      next
    end
    if line =~ any_version_regex && reading
      reading = false
      break
    end
    output = "#{output}#{line}" if reading
  end
  output
end

def docs
  execute('bundle exec jazzy')
end

def release
  branch = `git rev-parse --abbrev-ref HEAD`.strip
  unless branch.include?('version/')
    abort('Branch name should be version/x.x.x where x.x.x is the version')
  end

  # Bump version
  new_bundle_version, new_version = bump_version

  # Archiving
  archive_and_export
  execute("cd #{BUILD_PATH} && ditto -c -k --sequesterRsrc --keepParent #{APP_NAME}.app #{APP_NAME}.zip")

  # Commiting changes
  execute('git add .')
  execute("git commit -m 'Version #{new_version}'")
  execute("git tag #{new_version}")
  execute("git push --set-upstream origin version/#{new_version}")

  # Release
  client = Octokit::Client.new(access_token: GITHUB_TOKEN)
  changelog = changelog(new_version)
  release = client.create_release(REPOSITORY, new_version, name: new_version, body: changelog, draft: false)
  client.upload_asset(release.url, "#{BUILD_PATH}/#{APP_NAME}.zip",
                      content_type: 'application/zip')
end

def generate_project
  execute('swift package generate-xcodeproj')
end

desc 'Formats the swift code'
task :format do
  format
end

desc 'Builds the app'
task :build do
  build
end

desc 'Runs the unit tests'
task :test do
  test
end

desc 'Releases a new version of the app'
task :release do
  release
end

desc 'Runs all the continuous integration tasks'
task :ci do
  test
end

desc 'Generates the documentation'
task :docs do
  docs
end

desc 'Bumps the project minor version'
task :bump_version do
  bump_version
end

desc "Bootstraps the project"
task :bootstrap do
  generate_project
  execute('open App.xcworkspace')
end