defmodule Runner.QA.AppiumClient do
  @moduledoc """
  Manages Appium WebDriver sessions for iOS simulator automation.
  """

  alias WebDriverClient.Config

  @appium_server_url "http://localhost:4723"
  @session_timeout 90_000

  def start_session(simulator_uuid, app_bundle_id) do
    config =
      Config.build(@appium_server_url,
        protocol: :w3c,
        http_client_options: [
          recv_timeout: @session_timeout,
          timeout: @session_timeout
        ]
      )

    session_request = %{
      capabilities: %{
        alwaysMatch: %{
          "platformName" => "iOS",
          "appium:automationName" => "XCUITest",
          "appium:udid" => simulator_uuid,
          "appium:bundleId" => app_bundle_id,
          "appium:noReset" => true,
          "appium:newCommandTimeout" => 90
        }
      }
    }

    WebDriverClient.start_session(config, session_request)
  end

  def stop_session(session) do
    WebDriverClient.end_session(session)
  end

  def page_source(session) do
    WebDriverClient.fetch_page_source(session)
  end
end
