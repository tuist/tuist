# frozen_string_literal: true

Then("I should be able to access the documentation of target {string}") do |target|
  cmd = "swift run tuist doc --path #{@dir}/#{target}/ #{target}"
  io = IO.popen(cmd, :mode=>"r+") # merge standard output and standard error

  sleep 10 # This is important. If the request is done before the server is ready, it fails

  uri = URI.parse("http://localhost:4040/index.html")
  request = Net::HTTP::Get.new(uri)

  response = Net::HTTP.start(uri.hostname, uri.port) do |http|
    http.request(request)
  end

  flunk("The request to #{uri.to_s} returned status code #{response.code}") if response.code != "200"
  Process.kill("INT", io.pid)
end
