# frozen_string_literal: true

require 'semantic'
require 'octokit'
require 'date'
require 'dotenv/load'
require 'open3'

RELEASES_REPOSITORY = 'xcode-project-manager/xpm'
GITHUB_TOKEN = ENV['GH_TOKEN']
CHANGELOG_PATH = 'CHANGELOG.md'
PROJECT_PATH = "xpm.xcodeproj"

def execute(*command)
  system(*command) || abort
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

# def release
#   branch = `git rev-parse --abbrev-ref HEAD`.strip
#   unless branch.include?('version/')
#     abort('Branch name should be version/x.x.x where x.x.x is the version')
#   end

#   # Bump version
#   new_bundle_version, new_version = bump_version

#   # Archiving
#   archive_and_export
#   execute("cd #{BUILD_PATH} && ditto -c -k --sequesterRsrc --keepParent #{APP_NAME}.app #{APP_NAME}.zip")

#   # Commiting changes
#   execute('git add .')
#   execute("git commit -m 'Version #{new_version}'")
#   execute("git tag #{new_version}")
#   execute("git push --set-upstream origin version/#{new_version}")

#   # Release
#   client = Octokit::Client.new(access_token: GITHUB_TOKEN)
#   changelog = changelog(new_version)
#   release = client.create_release(REPOSITORY, new_version, name: new_version, body: changelog, draft: false)
#   client.upload_asset(release.url, "#{BUILD_PATH}/#{APP_NAME}.zip",
#                       content_type: 'application/zip')
# end

def generate_project
  execute('swift package generate-xcodeproj')
end

desc 'Formats the swift code'
task :format do
  execute('swiftformat .')
end

desc 'Builds the app'
task :build do
  execute("swift build")
end

desc 'Runs the unit tests'
task :test do
  execute("swift test")
end