defmodule Tuist.QA.ToolsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias LangChain.Message.ContentPart
  alias Tuist.QA.Client
  alias Tuist.QA.Tools

  setup :verify_on_exit!

  setup do
    tools =
      Tools.tools(%{
        server_url: "http://test.com",
        run_id: "test-run-id",
        auth_token: "test-token",
        account_handle: "test-account",
        project_handle: "test-project"
      })

    %{tools: tools}
  end

  describe "tools/0" do
    test "returns list of all available tools" do
      # Given
      expected_tools = [
        "describe_ui",
        "tap",
        "long_press",
        "swipe",
        "type_text",
        "key_press",
        "button",
        "touch",
        "gesture",
        "screenshot",
        "step_finished",
        "finalize"
      ]

      # When
      tools =
        Tools.tools(%{
          server_url: "http://test.com",
          run_id: "test-run-id",
          auth_token: "test-token",
          account_handle: "test-account",
          project_handle: "test-project"
        })

      tool_names = Enum.map(tools, & &1.name)

      # Then
      assert length(tools) == length(expected_tools)

      for tool_name <- expected_tools do
        assert tool_name in tool_names
      end
    end
  end

  describe "describe_ui tool" do
    test "successfully runs axe describe-ui command", %{tools: tools} do
      # Given
      simulator_uuid = "test-uuid"

      ui_output = """
      {
        "elements": [
          {"type": "Button", "frame": {"x": 100, "y": 200, "width": 80, "height": 40}}
        ]
      }
      """

      expect(System, :cmd, fn "/opt/homebrew/bin/axe", ["describe-ui", "--udid", ^simulator_uuid] ->
        {ui_output, 0}
      end)

      describe_ui_tool = Enum.find(tools, &(&1.name == "describe_ui"))

      # When
      result = describe_ui_tool.function.(%{"simulator_uuid" => simulator_uuid}, nil)

      # Then
      assert {:ok, _simplified_ui} = result
    end

    test "returns error when axe command fails", %{tools: tools} do
      # Given
      simulator_uuid = "test-uuid"

      expect(System, :cmd, fn "/opt/homebrew/bin/axe", ["describe-ui", "--udid", ^simulator_uuid] ->
        {"Command failed", 1}
      end)

      describe_ui_tool = Enum.find(tools, &(&1.name == "describe_ui"))

      # When
      result = describe_ui_tool.function.(%{"simulator_uuid" => simulator_uuid}, nil)

      # Then
      assert {:error, "axe command failed (status 1): Command failed"} = result
    end

    test "describes UI and simplifies AXe output", %{tools: tools} do
      # Given
      simulator_uuid = "test-uuid"

      ui_output = """
      [
        {
          "AXFrame" : "{{0, 0}, {393, 852}}",
          "AXUniqueId" : null,
          "frame" : {
            "y" : 0,
            "x" : 0,
            "width" : 393,
            "height" : 852
          },
          "role_description" : "application",
          "AXLabel" : "Tuist",
          "content_required" : false,
          "type" : "Application",
          "title" : null,
          "help" : null,
          "custom_actions" : [],
          "AXValue" : null,
          "enabled" : true,
          "role" : "AXApplication",
          "children" : [
            {
              "AXFrame" : "{{15.999999999999986, 101.33333333333333}, {143.33333333333331, 40.666666666666671}}",
              "AXUniqueId" : null,
              "frame" : {
                "y" : 101.33333333333333,
                "x" : 15.999999999999986,
                "width" : 143.33333333333331,
                "height" : 40.666666666666671
              },
              "role_description" : "heading",
              "AXLabel" : "Previews",
              "content_required" : false,
              "type" : "Heading",
              "title" : null,
              "help" : null,
              "custom_actions" : [],
              "AXValue" : null,
              "enabled" : true,
              "role" : "AXHeading",
              "children" : [],
              "subrole" : null,
              "pid" : 44977
            },
            {
              "AXFrame" : "{{305.66665649414062, 229.33332824707031}, {55.333343505859375, 28.333328247070312}}",
              "AXUniqueId" : null,
              "frame" : {
                "y" : 229.33332824707031,
                "x" : 305.66665649414062,
                "width" : 55.333343505859375,
                "height" : 28.333328247070312
              },
              "role_description" : "button",
              "AXLabel" : "Run",
              "content_required" : false,
              "type" : "Button",
              "title" : null,
              "help" : null,
              "custom_actions" : [],
              "AXValue" : null,
              "enabled" : false,
              "role" : "AXButton",
              "children" : [],
              "subrole" : null,
              "pid" : 44977
            }
          ],
          "subrole" : null,
          "pid" : 44977
        }
      ]
      """

      expect(System, :cmd, fn "/opt/homebrew/bin/axe", ["describe-ui", "--udid", ^simulator_uuid] ->
        {ui_output, 0}
      end)

      describe_ui_tool = Enum.find(tools, &(&1.name == "describe_ui"))

      # When
      result = describe_ui_tool.function.(%{"simulator_uuid" => simulator_uuid}, nil)

      # Then
      assert {:ok, simplified_ui} = result

      assert JSON.decode!(simplified_ui) == [
               %{
                 "type" => "Application",
                 "label" => "Tuist",
                 "frame" => %{"x" => 0, "y" => 0, "width" => 393, "height" => 852},
                 "children" => [
                   %{
                     "type" => "Heading",
                     "label" => "Previews",
                     "frame" => %{"x" => 16.0, "y" => 101.33, "width" => 143.33, "height" => 40.67}
                   },
                   %{
                     "type" => "Button",
                     "label" => "Run",
                     "enabled" => false,
                     "frame" => %{"x" => 305.67, "y" => 229.33, "width" => 55.33, "height" => 28.33}
                   }
                 ]
               }
             ]
    end
  end

  describe "tap tool" do
    test "successfully runs axe tap command", %{tools: tools} do
      # Given
      simulator_uuid = "test-uuid"
      x = 100
      y = 200

      expect(System, :cmd, fn "/opt/homebrew/bin/axe", ["tap", "-x", "100", "-y", "200", "--udid", ^simulator_uuid] ->
        {"Tap completed", 0}
      end)

      tap_tool = Enum.find(tools, &(&1.name == "tap"))

      # When
      result = tap_tool.function.(%{"simulator_uuid" => simulator_uuid, "x" => x, "y" => y}, nil)

      # Then
      assert {:ok, "Tap completed"} = result
    end

    test "returns error when tap command fails", %{tools: tools} do
      # Given
      simulator_uuid = "test-uuid"

      expect(System, :cmd, fn "/opt/homebrew/bin/axe", _ ->
        {"Tap failed", 1}
      end)

      tap_tool = Enum.find(tools, &(&1.name == "tap"))

      # When
      result = tap_tool.function.(%{"simulator_uuid" => simulator_uuid, "x" => 100, "y" => 200}, nil)

      # Then
      assert {:error, "axe command failed (status 1): Tap failed"} = result
    end
  end

  describe "screenshot tool" do
    test "successfully captures and uploads screenshot", %{tools: tools} do
      # Given
      simulator_uuid = "test-uuid"
      name = "login_screen"
      title = "Login Screen"
      temp_path = "/tmp/screenshot.png"
      image_data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      upload_url = "https://s3.example.com/upload-url"

      expect(Briefly, :create, fn -> {:ok, temp_path} end)

      expect(System, :cmd, fn "xcrun", ["simctl", "io", ^simulator_uuid, "screenshot", ^temp_path] ->
        {"", 0}
      end)

      expect(File, :read, fn ^temp_path -> {:ok, image_data} end)

      expect(Client, :screenshot_upload, fn %{
                                              file_name: ^name,
                                              title: ^title,
                                              server_url: "http://test.com",
                                              run_id: "test-run-id",
                                              auth_token: "test-token",
                                              account_handle: "test-account",
                                              project_handle: "test-project"
                                            } ->
        {:ok, %{"url" => upload_url}}
      end)

      expect(Req, :put, fn ^upload_url, [body: ^image_data, headers: [{"Content-Type", "image/png"}]] ->
        {:ok, %{status: 200}}
      end)

      expect(Client, :create_screenshot, fn %{
                                              file_name: ^name,
                                              title: ^title,
                                              server_url: "http://test.com",
                                              run_id: "test-run-id",
                                              auth_token: "test-token",
                                              account_handle: "test-account",
                                              project_handle: "test-project"
                                            } ->
        :ok
      end)

      screenshot_tool = Enum.find(tools, &(&1.name == "screenshot"))

      # When
      result =
        screenshot_tool.function.(%{"simulator_uuid" => simulator_uuid, "file_name" => name, "title" => title}, nil)

      # Then
      assert {:ok, %ContentPart{}} = result
    end

    test "returns error when screenshot command fails", %{tools: tools} do
      # Given
      simulator_uuid = "test-uuid"
      name = "error_screen"
      title = "Error Screen"
      temp_path = "/tmp/screenshot.png"

      expect(Briefly, :create, fn -> {:ok, temp_path} end)

      expect(System, :cmd, fn "xcrun", _ ->
        {"Screenshot failed", 1}
      end)

      screenshot_tool = Enum.find(tools, &(&1.name == "screenshot"))

      # When
      result =
        screenshot_tool.function.(%{"simulator_uuid" => simulator_uuid, "file_name" => name, "title" => title}, nil)

      # Then
      assert {:error, _} = result
    end

    test "returns error when upload URL request fails", %{tools: tools} do
      # Given
      simulator_uuid = "test-uuid"
      name = "failed_screen"
      title = "Failed Screen"
      temp_path = "/tmp/screenshot.png"
      image_data = <<137, 80, 78, 71, 13, 10, 26, 10>>

      expect(Briefly, :create, fn -> {:ok, temp_path} end)

      expect(System, :cmd, fn "xcrun", ["simctl", "io", ^simulator_uuid, "screenshot", ^temp_path] ->
        {"", 0}
      end)

      expect(File, :read, fn ^temp_path -> {:ok, image_data} end)

      expect(Client, :screenshot_upload, fn %{
                                              file_name: ^name,
                                              title: ^title,
                                              server_url: "http://test.com",
                                              run_id: "test-run-id",
                                              auth_token: "test-token",
                                              account_handle: "test-account",
                                              project_handle: "test-project"
                                            } ->
        {:error, "Server returned unexpected status 500"}
      end)

      screenshot_tool = Enum.find(tools, &(&1.name == "screenshot"))

      # When
      result =
        screenshot_tool.function.(%{"simulator_uuid" => simulator_uuid, "file_name" => name, "title" => title}, nil)

      # Then
      assert {:error, _} = result
    end
  end

  describe "type_text tool" do
    test "successfully types text", %{tools: tools} do
      # Given
      simulator_uuid = "test-uuid"
      text = "Hello World"

      expect(System, :cmd, fn "/opt/homebrew/bin/axe", ["type", ^text, "--udid", ^simulator_uuid] ->
        {"Text typed", 0}
      end)

      type_text_tool = Enum.find(tools, &(&1.name == "type_text"))

      # When
      result = type_text_tool.function.(%{"simulator_uuid" => simulator_uuid, "text" => text}, nil)

      # Then
      assert {:ok, "Text typed"} = result
    end
  end

  describe "swipe tool" do
    test "successfully performs swipe with default duration", %{tools: tools} do
      # Given
      simulator_uuid = "test-uuid"
      from_x = 100
      from_y = 200
      to_x = 300
      to_y = 400

      expect(System, :cmd, fn "/opt/homebrew/bin/axe",
                              [
                                "swipe",
                                "--start-x",
                                "100",
                                "--start-y",
                                "200",
                                "--end-x",
                                "300",
                                "--end-y",
                                "400",
                                "--duration",
                                "0.5",
                                "--udid",
                                ^simulator_uuid
                              ] ->
        {"Swipe completed", 0}
      end)

      swipe_tool = Enum.find(tools, &(&1.name == "swipe"))

      # When
      result =
        swipe_tool.function.(
          %{
            "simulator_uuid" => simulator_uuid,
            "from_x" => from_x,
            "from_y" => from_y,
            "to_x" => to_x,
            "to_y" => to_y
          },
          nil
        )

      # Then
      assert {:ok, "Swipe was successful"} = result
    end

    test "successfully performs swipe with custom duration", %{tools: tools} do
      # Given
      simulator_uuid = "test-uuid"
      duration = 1.5

      expect(System, :cmd, fn "/opt/homebrew/bin/axe",
                              [
                                "swipe",
                                "--start-x",
                                "100",
                                "--start-y",
                                "200",
                                "--end-x",
                                "300",
                                "--end-y",
                                "400",
                                "--duration",
                                "1.5",
                                "--udid",
                                ^simulator_uuid
                              ] ->
        {"Swipe completed", 0}
      end)

      swipe_tool = Enum.find(tools, &(&1.name == "swipe"))

      # When
      result =
        swipe_tool.function.(
          %{
            "simulator_uuid" => simulator_uuid,
            "from_x" => 100,
            "from_y" => 200,
            "to_x" => 300,
            "to_y" => 400,
            "duration" => duration
          },
          nil
        )

      # Then
      assert {:ok, "Swipe was successful"} = result
    end
  end

  describe "gesture tool" do
    test "successfully performs scroll-up gesture", %{tools: tools} do
      # Given
      simulator_uuid = "test-uuid"
      preset = "scroll-up"

      expect(System, :cmd, fn "/opt/homebrew/bin/axe", ["gesture", ^preset, "--udid", ^simulator_uuid] ->
        {"Gesture completed", 0}
      end)

      gesture_tool = Enum.find(tools, &(&1.name == "gesture"))

      params = %{
        "simulator_uuid" => simulator_uuid,
        "preset" => preset
      }

      # When
      result = gesture_tool.function.(params, nil)

      # Then
      assert {:ok, "Gesture was successful"} = result
    end

    test "successfully performs gesture with optional parameters", %{tools: tools} do
      # Given
      simulator_uuid = "test-uuid"
      preset = "scroll-down"
      duration = 1.0
      delta = 200

      expect(System, :cmd, fn "/opt/homebrew/bin/axe",
                              [
                                "gesture",
                                ^preset,
                                "--duration",
                                "1.0",
                                "--delta",
                                "200",
                                "--udid",
                                ^simulator_uuid
                              ] ->
        {"Gesture completed", 0}
      end)

      gesture_tool = Enum.find(tools, &(&1.name == "gesture"))

      # When
      result =
        gesture_tool.function.(
          %{
            "simulator_uuid" => simulator_uuid,
            "preset" => preset,
            "duration" => duration,
            "delta" => delta
          },
          nil
        )

      # Then
      assert {:ok, "Gesture was successful"} = result
    end
  end

  describe "button tool" do
    test "successfully presses home button", %{tools: tools} do
      # Given
      simulator_uuid = "test-uuid"
      button = "home"

      expect(System, :cmd, fn "/opt/homebrew/bin/axe", ["button", ^button, "--udid", ^simulator_uuid] ->
        {"Button pressed", 0}
      end)

      button_tool = Enum.find(tools, &(&1.name == "button"))

      # When
      result = button_tool.function.(%{"simulator_uuid" => simulator_uuid, "button" => button}, nil)

      # Then
      assert {:ok, "Button pressed"} = result
    end
  end

  describe "step_finished tool" do
    test "returns confirmation message on success", %{tools: tools} do
      # Given
      summary = "Successfully completed login test"
      description = "User successfully entered credentials and was able to access the main dashboard"
      issues = ["Minor UI alignment issue in login button"]

      expect(Client, :create_step, fn %{
                                        summary: ^summary,
                                        description: ^description,
                                        issues: ^issues,
                                        server_url: "http://test.com",
                                        run_id: "test-run-id",
                                        auth_token: "test-token",
                                        account_handle: "test-account",
                                        project_handle: "test-project"
                                      } ->
        :ok
      end)

      step_finished_tool = Enum.find(tools, &(&1.name == "step_finished"))

      # When
      result =
        step_finished_tool.function.(
          %{
            "summary" => summary,
            "description" => description,
            "issues" => issues
          },
          nil
        )

      # Then
      assert {:ok,
              "Step finished and reported. Screenshots have been associated with this step. Continue with your testing."} =
               result
    end

    test "returns error on failure", %{tools: tools} do
      # Given
      summary = "Failed test step"
      description = "Test failed due to timeout"
      issues = ["Timeout error", "Server unresponsive"]

      expect(Client, :create_step, fn %{
                                        summary: ^summary,
                                        description: ^description,
                                        issues: ^issues,
                                        server_url: "http://test.com",
                                        run_id: "test-run-id",
                                        auth_token: "test-token",
                                        account_handle: "test-account",
                                        project_handle: "test-project"
                                      } ->
        {:error, "Server returned unexpected status 500"}
      end)

      step_finished_tool = Enum.find(tools, &(&1.name == "step_finished"))

      # When
      result =
        step_finished_tool.function.(
          %{
            "summary" => summary,
            "description" => description,
            "issues" => issues
          },
          nil
        )

      # Then
      assert {:error, "Failed to report step: Server returned unexpected status 500"} = result
    end
  end

  describe "finalize tool" do
    test "returns summary and status on success", %{tools: tools} do
      # Given
      summary = "Test completed successfully"

      expect(Client, :finalize_run, fn %{
                                         summary: ^summary,
                                         server_url: "http://test.com",
                                         run_id: "test-run-id",
                                         auth_token: "test-token",
                                         account_handle: "test-account",
                                         project_handle: "test-project"
                                       } ->
        {:ok, "success"}
      end)

      finalize_tool = Enum.find(tools, &(&1.name == "finalize"))

      # When
      result = finalize_tool.function.(%{"summary" => summary}, nil)

      # Then
      assert {:ok, "QA test run finished successfully and status updated."} = result
    end

    test "returns error on failure", %{tools: tools} do
      # Given
      summary = "Failed test run"

      expect(Client, :finalize_run, fn %{
                                         summary: ^summary,
                                         server_url: "http://test.com",
                                         run_id: "test-run-id",
                                         auth_token: "test-token",
                                         account_handle: "test-account",
                                         project_handle: "test-project"
                                       } ->
        {:error, "Server returned unexpected status 404"}
      end)

      finalize_tool = Enum.find(tools, &(&1.name == "finalize"))

      # When
      result = finalize_tool.function.(%{"summary" => summary}, nil)

      # Then
      assert {:error, "Failed to update run status: Server returned unexpected status 404"} = result
    end
  end
end
