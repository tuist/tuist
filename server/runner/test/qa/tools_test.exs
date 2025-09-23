defmodule Runner.QA.ToolsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias LangChain.Message.ContentPart
  alias Runner.QA.AppiumClient
  alias Runner.QA.Client
  alias Runner.QA.Sleeper
  alias Runner.QA.Tools

  setup :verify_on_exit!

  setup do
    # Stub the Sleeper module to avoid delays in tests
    stub(Sleeper, :sleep, fn _ -> :ok end)

    tools =
      Tools.tools(%{
        server_url: "http://test.com",
        run_id: "test-run-id",
        auth_token: "test-token",
        account_handle: "test-account",
        project_handle: "test-project",
        bundle_identifier: "com.test.app",
        appium_session: %{id: "mock-session"},
        simulator_uuid: "test-uuid"
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
        "plan_report",
        "step_report",
        "finalize"
      ]

      # When
      tools =
        Tools.tools(%{
          server_url: "http://test.com",
          run_id: "test-run-id",
          auth_token: "test-token",
          account_handle: "test-account",
          project_handle: "test-project",
          bundle_identifier: "com.test.app",
          appium_session: %{id: "mock-session"},
          simulator_uuid: "test-uuid"
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
    test "successfully gets page source from Appium", %{tools: tools} do
      # Given
      session = %{id: "mock-session"}

      xml_output = """
      <XCUIElementTypeApplication name="TestApp" label="TestApp" visible="true" enabled="true" x="0" y="0" width="393" height="852">
        <XCUIElementTypeButton name="Login" label="Login" visible="true" enabled="true" x="100" y="200" width="80" height="40"/>
      </XCUIElementTypeApplication>
      """

      expect(AppiumClient, :page_source, fn ^session ->
        {:ok, xml_output}
      end)

      describe_ui_tool = Enum.find(tools, &(&1.name == "describe_ui"))

      # When
      result = describe_ui_tool.function.(%{}, nil)

      # Then
      assert {:ok, [content_part]} = result
      assert %ContentPart{type: :text, content: content} = content_part
      assert content =~ "XCUIElementTypeButton"
    end
  end

  describe "tap tool" do
    test "successfully runs axe tap command", %{tools: tools} do
      # Given
      simulator_uuid = "test-uuid"
      x = 100
      y = 200
      step_id = "test-step-id"
      temp_path = "/tmp/screenshot.png"
      image_data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      upload_url = "https://s3.example.com/upload-url"

      expect(System, :cmd, fn "/opt/homebrew/bin/axe", ["tap", "-x", "100", "-y", "200", "--udid", ^simulator_uuid] ->
        {"Tap completed", 0}
      end)

      expect(Client, :create_step, fn %{action: "Test tap", started_at: started_at}
                                      when is_struct(started_at, DateTime) ->
        {:ok, step_id}
      end)

      expect(Briefly, :create, fn -> {:ok, temp_path} end)

      expect(System, :cmd, fn "xcrun", ["simctl", "io", ^simulator_uuid, "screenshot", ^temp_path] ->
        {"", 0}
      end)

      expect(File, :read, fn ^temp_path -> {:ok, image_data} end)
      expect(Client, :create_screenshot, fn _ -> {:ok, %{"id" => "screenshot-123", "upload_url" => upload_url}} end)
      stub(Req, :put, fn ^upload_url, _ -> {:ok, %{status: 200}} end)

      session = %{id: "mock-session"}
      expect(AppiumClient, :page_source, fn ^session -> {:ok, "<XCUIElementTypeApplication/>"} end)

      tap_tool = Enum.find(tools, &(&1.name == "tap"))

      # When
      result =
        tap_tool.function.(
          %{"x" => x, "y" => y, "action" => "Test tap"},
          nil
        )

      # Then
      assert {:ok, [_screenshot, _ui_state, _message]} = result
    end

    test "returns error when tap command fails", %{tools: tools} do
      # Given
      simulator_uuid = "test-uuid"

      expect(System, :cmd, fn "/opt/homebrew/bin/axe", ["tap", "-x", "100", "-y", "200", "--udid", ^simulator_uuid] ->
        {"Tap failed", 1}
      end)

      tap_tool = Enum.find(tools, &(&1.name == "tap"))

      # When
      result =
        tap_tool.function.(
          %{"x" => 100, "y" => 200, "action" => "Test tap"},
          nil
        )

      # Then
      assert {:error, "axe command failed (status 1): Tap failed"} = result
    end
  end

  describe "screenshot tool" do
    test "successfully captures and uploads screenshot", %{tools: tools} do
      # Given
      simulator_uuid = "test-uuid"
      temp_path = "/tmp/screenshot.png"
      image_data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      screenshot_id = "test-screenshot-id"
      upload_url = "https://s3.amazonaws.com/upload"

      expect(Briefly, :create, fn -> {:ok, temp_path} end)

      expect(System, :cmd, fn "xcrun", ["simctl", "io", ^simulator_uuid, "screenshot", ^temp_path] ->
        {"", 0}
      end)

      expect(File, :read, fn ^temp_path -> {:ok, image_data} end)

      expect(Client, :create_screenshot, fn %{
                                              server_url: "http://test.com",
                                              run_id: "test-run-id",
                                              auth_token: "test-token",
                                              account_handle: "test-account",
                                              project_handle: "test-project",
                                              step_id: step_id
                                            }
                                            when is_binary(step_id) ->
        {:ok, %{"id" => screenshot_id, "upload_url" => upload_url}}
      end)

      expect(Req, :put, fn ^upload_url, [body: ^image_data, headers: [{"Content-Type", "image/png"}]] ->
        {:ok, %{}}
      end)

      screenshot_tool = Enum.find(tools, &(&1.name == "screenshot"))

      # When
      result = screenshot_tool.function.(%{}, nil)

      # Then
      assert {:ok, content_part} = result
      assert content_part.type == :text
      assert content_part.content =~ "screenshot_id"
      assert content_part.content =~ screenshot_id
      assert content_part.content =~ "test-run-id"
    end

    test "returns error when screenshot command fails", %{tools: tools} do
      # Given
      simulator_uuid = "test-uuid"
      temp_path = "/tmp/screenshot.png"

      expect(Briefly, :create, fn -> {:ok, temp_path} end)

      expect(System, :cmd, fn "xcrun", ["simctl", "io", ^simulator_uuid, "screenshot", ^temp_path] ->
        {"Screenshot command failed", 1}
      end)

      screenshot_tool = Enum.find(tools, &(&1.name == "screenshot"))

      # When
      result =
        screenshot_tool.function.(%{}, nil)

      # Then
      assert {:error, "Failed to capture screenshot: Screenshot command failed"} = result
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

      step_id = "test-step-id"
      temp_path = "/tmp/screenshot.png"
      image_data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      upload_url = "https://s3.example.com/upload-url"

      expect(Client, :create_step, fn %{action: "Test typing", started_at: started_at}
                                      when is_struct(started_at, DateTime) ->
        {:ok, step_id}
      end)

      expect(Briefly, :create, fn -> {:ok, temp_path} end)

      expect(System, :cmd, fn "xcrun", ["simctl", "io", ^simulator_uuid, "screenshot", ^temp_path] ->
        {"", 0}
      end)

      expect(File, :read, fn ^temp_path -> {:ok, image_data} end)
      expect(Client, :create_screenshot, fn _ -> {:ok, %{"id" => "screenshot-123", "upload_url" => upload_url}} end)
      stub(Req, :put, fn ^upload_url, _ -> {:ok, %{status: 200}} end)

      session = %{id: "mock-session"}
      expect(AppiumClient, :page_source, fn ^session -> {:ok, "<XCUIElementTypeApplication/>"} end)

      type_text_tool = Enum.find(tools, &(&1.name == "type_text"))

      # When
      result =
        type_text_tool.function.(
          %{"text" => text, "action" => "Test typing"},
          nil
        )

      # Then
      assert {:ok, [_screenshot, _ui_state, _message]} = result
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

      step_id = "test-step-id"
      temp_path = "/tmp/screenshot.png"
      image_data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      upload_url = "https://s3.example.com/upload-url"

      expect(Client, :create_step, fn %{action: "Test swipe", started_at: started_at}
                                      when is_struct(started_at, DateTime) ->
        {:ok, step_id}
      end)

      expect(Briefly, :create, fn -> {:ok, temp_path} end)

      expect(System, :cmd, fn "xcrun", ["simctl", "io", ^simulator_uuid, "screenshot", ^temp_path] ->
        {"", 0}
      end)

      expect(File, :read, fn ^temp_path -> {:ok, image_data} end)
      expect(Client, :create_screenshot, fn _ -> {:ok, %{"id" => "screenshot-123", "upload_url" => upload_url}} end)
      stub(Req, :put, fn ^upload_url, _ -> {:ok, %{status: 200}} end)

      session = %{id: "mock-session"}
      expect(AppiumClient, :page_source, fn ^session -> {:ok, "<XCUIElementTypeApplication/>"} end)

      swipe_tool = Enum.find(tools, &(&1.name == "swipe"))

      # When
      result =
        swipe_tool.function.(
          %{
            "from_x" => from_x,
            "from_y" => from_y,
            "to_x" => to_x,
            "to_y" => to_y,
            "action" => "Test swipe"
          },
          nil
        )

      # Then
      assert {:ok, [_screenshot, _ui_state, _message]} = result
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

      step_id = "test-step-id"
      temp_path = "/tmp/screenshot.png"
      image_data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      upload_url = "https://s3.example.com/upload-url"

      expect(Client, :create_step, fn %{action: "Test swipe with duration", started_at: started_at}
                                      when is_struct(started_at, DateTime) ->
        {:ok, step_id}
      end)

      expect(Briefly, :create, fn -> {:ok, temp_path} end)

      expect(System, :cmd, fn "xcrun", ["simctl", "io", ^simulator_uuid, "screenshot", ^temp_path] ->
        {"", 0}
      end)

      expect(File, :read, fn ^temp_path -> {:ok, image_data} end)
      expect(Client, :create_screenshot, fn _ -> {:ok, %{"id" => "screenshot-123", "upload_url" => upload_url}} end)
      stub(Req, :put, fn ^upload_url, _ -> {:ok, %{status: 200}} end)

      session = %{id: "mock-session"}
      expect(AppiumClient, :page_source, fn ^session -> {:ok, "<XCUIElementTypeApplication/>"} end)

      swipe_tool = Enum.find(tools, &(&1.name == "swipe"))

      # When
      result =
        swipe_tool.function.(
          %{
            "from_x" => 100,
            "from_y" => 200,
            "to_x" => 300,
            "to_y" => 400,
            "duration" => duration,
            "action" => "Test swipe with duration"
          },
          nil
        )

      # Then
      assert {:ok, [_screenshot, _ui_state, _message]} = result
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

      step_id = "test-step-id"
      temp_path = "/tmp/screenshot.png"
      image_data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      upload_url = "https://s3.example.com/upload-url"

      expect(Client, :create_step, fn %{action: "Test gesture", started_at: started_at}
                                      when is_struct(started_at, DateTime) ->
        {:ok, step_id}
      end)

      expect(Briefly, :create, fn -> {:ok, temp_path} end)

      expect(System, :cmd, fn "xcrun", ["simctl", "io", ^simulator_uuid, "screenshot", ^temp_path] ->
        {"", 0}
      end)

      expect(File, :read, fn ^temp_path -> {:ok, image_data} end)
      expect(Client, :create_screenshot, fn _ -> {:ok, %{"id" => "screenshot-123", "upload_url" => upload_url}} end)
      stub(Req, :put, fn ^upload_url, _ -> {:ok, %{status: 200}} end)

      session = %{id: "mock-session"}
      expect(AppiumClient, :page_source, fn ^session -> {:ok, "<XCUIElementTypeApplication/>"} end)

      gesture_tool = Enum.find(tools, &(&1.name == "gesture"))

      params = %{
        "preset" => preset,
        "action" => "Test gesture"
      }

      # When
      result = gesture_tool.function.(params, nil)

      # Then
      assert {:ok, [_screenshot, _ui_state, _message]} = result
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

      step_id = "test-step-id"
      temp_path = "/tmp/screenshot.png"
      image_data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      upload_url = "https://s3.example.com/upload-url"

      expect(Client, :create_step, fn %{action: "Test gesture with params", started_at: started_at}
                                      when is_struct(started_at, DateTime) ->
        {:ok, step_id}
      end)

      expect(Briefly, :create, fn -> {:ok, temp_path} end)

      expect(System, :cmd, fn "xcrun", ["simctl", "io", ^simulator_uuid, "screenshot", ^temp_path] ->
        {"", 0}
      end)

      expect(File, :read, fn ^temp_path -> {:ok, image_data} end)
      expect(Client, :create_screenshot, fn _ -> {:ok, %{"id" => "screenshot-123", "upload_url" => upload_url}} end)
      stub(Req, :put, fn ^upload_url, _ -> {:ok, %{status: 200}} end)

      session = %{id: "mock-session"}
      expect(AppiumClient, :page_source, fn ^session -> {:ok, "<XCUIElementTypeApplication/>"} end)

      gesture_tool = Enum.find(tools, &(&1.name == "gesture"))

      # When
      result =
        gesture_tool.function.(
          %{
            "preset" => preset,
            "duration" => duration,
            "delta" => delta,
            "action" => "Test gesture with params"
          },
          nil
        )

      # Then
      assert {:ok, [_screenshot, _ui_state, _message]} = result
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

      step_id = "test-step-id"
      temp_path = "/tmp/screenshot.png"
      image_data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      upload_url = "https://s3.example.com/upload-url"

      expect(Client, :create_step, fn %{action: "Test button", started_at: started_at}
                                      when is_struct(started_at, DateTime) ->
        {:ok, step_id}
      end)

      expect(Briefly, :create, fn -> {:ok, temp_path} end)

      expect(System, :cmd, fn "xcrun", ["simctl", "io", ^simulator_uuid, "screenshot", ^temp_path] ->
        {"", 0}
      end)

      expect(File, :read, fn ^temp_path -> {:ok, image_data} end)
      expect(Client, :create_screenshot, fn _ -> {:ok, %{"id" => "screenshot-123", "upload_url" => upload_url}} end)
      stub(Req, :put, fn ^upload_url, _ -> {:ok, %{status: 200}} end)

      session = %{id: "mock-session"}
      expect(AppiumClient, :page_source, fn ^session -> {:ok, "<XCUIElementTypeApplication/>"} end)

      button_tool = Enum.find(tools, &(&1.name == "button"))

      # When
      result =
        button_tool.function.(
          %{"button" => button, "action" => "Test button"},
          nil
        )

      # Then
      assert {:ok, [_screenshot, _ui_state, _message]} = result
    end
  end

  describe "step_report tool" do
    test "returns confirmation message on success", %{tools: tools} do
      # Given
      step_id = "test-step-id"
      result = "Successfully completed login test"
      issues = ["Minor UI alignment issue in login button"]

      expect(Client, :start_update_step, fn %{
                                              step_id: ^step_id,
                                              result: ^result,
                                              issues: ^issues,
                                              server_url: "http://test.com",
                                              run_id: "test-run-id",
                                              auth_token: "test-token",
                                              account_handle: "test-account",
                                              project_handle: "test-project"
                                            } ->
        {:ok, :async}
      end)

      step_report_tool = Enum.find(tools, &(&1.name == "step_report"))

      # When
      result_response =
        step_report_tool.function.(
          %{
            "step_id" => step_id,
            "result" => result,
            "issues" => issues
          },
          nil
        )

      # Then
      assert {:ok, "Step report submitted asynchronously."} = result_response
    end

    test "returns success even for error cases (async)", %{tools: tools} do
      # Given
      step_id = "test-step-id"
      result = "Failed test step"
      issues = ["Timeout error", "Server unresponsive"]

      expect(Client, :start_update_step, fn %{
                                              step_id: ^step_id,
                                              result: ^result,
                                              issues: ^issues,
                                              server_url: "http://test.com",
                                              run_id: "test-run-id",
                                              auth_token: "test-token",
                                              account_handle: "test-account",
                                              project_handle: "test-project"
                                            } ->
        {:ok, :async}
      end)

      step_report_tool = Enum.find(tools, &(&1.name == "step_report"))

      # When
      result_response =
        step_report_tool.function.(
          %{
            "step_id" => step_id,
            "result" => result,
            "issues" => issues
          },
          nil
        )

      # Then
      assert {:ok, "Step report submitted asynchronously."} = result_response
    end
  end

  describe "plan_report tool" do
    test "successfully reports QA plan and captures initial screenshot", %{tools: tools} do
      # Given
      simulator_uuid = "test-uuid"
      summary = "Test login functionality"

      details =
        "Test that users can successfully log in with valid credentials and receive appropriate error messages for invalid credentials"

      step_id = "test-step-id"
      temp_path = "/tmp/screenshot.png"
      image_data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      upload_url = "https://s3.example.com/upload-url"

      expect(Client, :create_step, fn %{
                                        action: ^summary,
                                        result: ^details,
                                        issues: [],
                                        server_url: "http://test.com",
                                        run_id: "test-run-id",
                                        auth_token: "test-token",
                                        account_handle: "test-account",
                                        project_handle: "test-project"
                                      } ->
        {:ok, step_id}
      end)

      expect(Briefly, :create, fn -> {:ok, temp_path} end)

      expect(System, :cmd, fn "xcrun", ["simctl", "io", ^simulator_uuid, "screenshot", ^temp_path] ->
        {"", 0}
      end)

      expect(File, :read, fn ^temp_path -> {:ok, image_data} end)
      expect(Client, :create_screenshot, fn _ -> {:ok, %{"id" => "screenshot-123", "upload_url" => upload_url}} end)
      stub(Req, :put, fn ^upload_url, _ -> {:ok, %{status: 200}} end)

      plan_report_tool = Enum.find(tools, &(&1.name == "plan_report"))

      # When
      result =
        plan_report_tool.function.(
          %{
            "summary" => summary,
            "details" => details
          },
          nil
        )

      # Then
      assert {:ok, [screenshot, message]} = result
      assert %ContentPart{} = screenshot

      assert %ContentPart{
               content: "The QA plan has been documented and the initial app state screenshot has been captured."
             } = message
    end
  end

  describe "finalize tool" do
    test "returns status on success", %{tools: tools} do
      # Given
      expect(Client, :finalize_run, fn %{
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
      result = finalize_tool.function.(%{}, nil)

      # Then
      assert {:ok, "QA test run finished successfully and status updated."} = result
    end

    test "returns error on failure", %{tools: tools} do
      # Given
      expect(Client, :finalize_run, fn %{
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
      result = finalize_tool.function.(%{}, nil)

      # Then
      assert {:error, "Failed to update run status: Server returned unexpected status 404"} =
               result
    end
  end
end
