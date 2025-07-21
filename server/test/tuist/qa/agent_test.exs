defmodule Tuist.QA.AgentTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Tuist.QA.Agent
  alias Tuist.QA.SimulatorController
  alias Tuist.QA.SimulatorDevice
  alias Tuist.Zip

  describe "test/1" do
    test "runs agentic tests" do
      # Given
      preview_url = "https://example.com/preview.zip"
      api_key = "test_api_key"
      bundle_identifier = "com.example.myapp"

      device = %SimulatorDevice{
        name: "iPhone 16",
        udid: "TEST-DEVICE-UUID",
        state: "Shutdown",
        runtime_identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-5"
      }

      stub(Briefly, :create, fn opts ->
        case opts do
          [extname: ".zip"] ->
            {:ok, "/tmp/preview_test.zip"}

          [directory: true] ->
            {:ok, "/tmp/preview_extract_test"}
        end
      end)

      zip_path = "/tmp/preview_test.zip"

      stub(File, :stream!, fn ^zip_path ->
        :mocked_stream
      end)

      stub(File, :ls, fn _dir ->
        {:ok, ["MyApp.app", "README.txt"]}
      end)

      stub(Req, :get, fn ^preview_url, _________opts ->
        {:ok, %{status: 200}}
      end)

      zip_charlist = String.to_charlist("/tmp/preview_test.zip")
      extract_opts = [{:cwd, String.to_charlist("/tmp/preview_extract_test")}]

      stub(Zip, :extract, fn ^zip_charlist, ^extract_opts ->
        {:ok, []}
      end)

      stub(SimulatorController, :devices, fn _opts ->
        {:ok, [device]}
      end)

      stub(SimulatorController, :boot_simulator, fn ^device ->
        :ok
      end)

      app_path = "/tmp/preview_extract_test/MyApp.app"

      stub(SimulatorController, :install_app, fn ^app_path, ^device ->
        :ok
      end)

      stub(SimulatorController, :launch_app, fn ^bundle_identifier, ^device ->
        :ok
      end)

      # When
      result =
        Agent.test(%{
          api_key: api_key,
          preview_url: preview_url,
          bundle_identifier: bundle_identifier
        })

      # Then
      assert result == :ok
    end
  end
end
