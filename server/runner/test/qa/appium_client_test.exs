defmodule Runner.QA.AppiumClientTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Runner.QA.AppiumClient

  describe "start_session/2" do
    test "starts WebDriver session with correct configuration" do
      # Given
      simulator_uuid = "test-uuid-123"
      app_bundle_id = "com.test.app"

      expect(WebDriverClient, :start_session, fn config, session_request ->
        assert config.base_url == "http://localhost:4723"

        assert session_request == %{
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

        {:ok, %{id: "session-123"}}
      end)

      # When
      result = AppiumClient.start_session(simulator_uuid, app_bundle_id)

      # Then
      assert result == {:ok, %{id: "session-123"}}
    end
  end

  describe "stop_session/1" do
    test "ends WebDriver session" do
      # Given
      session = %{id: "session-123"}

      expect(WebDriverClient, :end_session, fn ^session ->
        :ok
      end)

      # When
      result = AppiumClient.stop_session(session)

      # Then
      assert result == :ok
    end
  end

  describe "page_source/1" do
    test "fetches page source from session" do
      # Given
      session = %{id: "session-123"}
      page_source = "<XCUIElementTypeApplication>...</XCUIElementTypeApplication>"

      expect(WebDriverClient, :fetch_page_source, fn ^session ->
        {:ok, page_source}
      end)

      # When
      result = AppiumClient.page_source(session)

      # Then
      assert result == {:ok, page_source}
    end
  end
end
