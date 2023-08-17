# frozen_string_literal: true

# Service for authenticating the CLI
class CliAuthService < ApplicationService
  attr_reader :user

  def initialize(user:)
    super()
    @user = user
  end

  def call
    puts "Do an auth request to the CLI"
    url = URI.parse("http://127.0.0.1:4545/auth?token=#{user.token}&account=#{user.account.name}")

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = (url.scheme == 'https')

    request = Net::HTTP::Get.new(url.request_uri)
    http.request(request)
  end
end
