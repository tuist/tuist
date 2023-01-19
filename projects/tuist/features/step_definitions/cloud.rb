# frozen_string_literal: true

require "xcodeproj"


# Uses exponential back-off technique for waiting for the cloud server
# Taken from: https://github.com/lucassus/mongo_browser/commit/cc6ed556e3cb2b2510c027ae0791828b6501b5c9
def wait_until_responsive
  wait_time = 0.01
  timeout = 100
  start_time = Time.now

  until responsive?
    raise "Could not start cloud server" if Time.now - start_time >= timeout

    sleep(wait_time)
    wait_time *= 2
  end
end

def responsive?
  begin
    http = Net::HTTP.start("127.0.0.1", 3000, {open_timeout: 5, read_timeout: 5})
    response = http.head("/")
    response.code == "200"
  rescue
    false
  end
end

And(/^I run a local tuist cloud server$/) do
  @cloud_root = File.expand_path("../../../cloud/", __dir__)
  @rails = "BUNDLE_GEMFILE=\"#{File.join(@cloud_root, "Gemfile")}\" #{@cloud_root}/bin/rails"
  if responsive? == false
    cmd = "#{@rails} server --port 3000"
    @pid = spawn(cmd)
    wait_until_responsive
  end
end

Then(/^tuist inits new cloud project$/) do
  uuid = SecureRandom.uuid[0...10]
  account_name, account_name_err, account_name_status = Open3.capture3(
    "#{@rails} testing:get_account_name -f #{@cloud_root}/Rakefile"
  )
  flunk(account_name_err) unless account_name_status.success?
  token, token_err, token_status = Open3.capture3(
    "#{@rails} testing:get_token #{account_name.strip} -f #{@cloud_root}/Rakefile"
  )
  flunk(token_err) unless token_status.success?
  out, err, status = Open3.capture3(
    { "TUIST_CONFIG_CLOUD_TOKEN" => token.strip },
    @tuist, "cloud", "init", "--name", uuid, "--url", "http://127.0.0.1:3000/"
  )
  flunk(err) unless status.success?
  assert(
    out.include?("cloud: .cloud(projectId: \"#{account_name.strip}/#{uuid}\", url: \"http://127.0.0.1:3000/\")"),
    "The cloud project was not created properly"
  )
end

After do |_scenario|
  Process.kill("QUIT", @pid) unless @pid.nil?
end
