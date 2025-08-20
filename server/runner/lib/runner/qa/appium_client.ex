defmodule Runner.QA.AppiumClient do
  @moduledoc """
  Manages Appium WebDriver sessions for iOS simulator automation.
  """

  alias WebDriverClient.Config

  require Logger

  @appium_server_url "http://localhost:4723"
  @session_timeout 30_000

  def start_session(simulator_uuid, app_bundle_id) do
    config =
      Config.build(@appium_server_url,
        protocol: :w3c,
        http_client_options: [
          recv_timeout: @session_timeout,
          timeout: @session_timeout
        ]
      )

    # W3C WebDriver session request format
    session_request = %{
      capabilities: %{
        alwaysMatch: %{
          "platformName" => "iOS",
          "appium:automationName" => "XCUITest",
          "appium:udid" => simulator_uuid,
          "appium:bundleId" => app_bundle_id,
          "appium:noReset" => true,
          "appium:newCommandTimeout" => 300
        }
      }
    }

    case WebDriverClient.start_session(config, session_request) do
      {:ok, session} ->
        {:ok, session}

      {:error, %WebDriverClient.ConnectionError{} = error} ->
        Logger.error("Failed to connect to Appium server at #{@appium_server_url}: #{error.message}")
        Logger.error("Make sure Appium server is running with: appium --base-path / --allow-cors")
        {:error, "Appium connection failed: #{error.message}"}

      {:error, %WebDriverClient.WebDriverError{} = error} ->
        Logger.error("Appium WebDriver error: #{error.message}")
        {:error, error.message}

      {:error, reason} ->
        Logger.error("Failed to start Appium session: #{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end

  def stop_session(session) do
    WebDriverClient.end_session(session)
  end

  def get_page_source(session) do
    case WebDriverClient.fetch_page_source(session) do
      {:ok, source} ->
        {:ok, source}

      {:error, reason} ->
        Logger.error("Failed to get page source: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def find_element(session, strategy, value) do
    WebDriverClient.find_element(session, strategy, value)
  end

  def find_elements(session, strategy, value) do
    WebDriverClient.find_elements(session, strategy, value)
  end

  def get_element_attribute(session, element, attribute) do
    WebDriverClient.fetch_element_attribute(session, element, attribute)
  end

  def get_element_rect(_session, _element) do
    # WebDriverClient doesn't support fetch_element_rect
    # This would need to be implemented using element attributes
    {:error, "get_element_rect not implemented"}
  end

  def tap_element(session, element) do
    WebDriverClient.click_element(session, element)
  end

  def tap_coordinates(_session, _x, _y) do
    # WebDriverClient doesn't support perform_actions
    # This would need to be implemented differently
    {:error, "tap_coordinates not implemented"}
  end
end
