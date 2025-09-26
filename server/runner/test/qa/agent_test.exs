defmodule Runner.QA.AgentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Message
  alias LangChain.Message.ContentPart
  alias LangChain.Message.ToolResult
  alias Runner.QA.Agent
  alias Runner.QA.AppiumClient
  alias Runner.QA.Client
  alias Runner.QA.Simulators
  alias Runner.QA.Simulators.SimulatorDevice
  alias Runner.QA.Sleeper
  alias Runner.QA.Tools

  setup do
    device = %SimulatorDevice{
      name: "iPhone 17",
      udid: "42172B88-9A53-46C8-B560-75609012CF0D",
      state: "Booted",
      runtime_identifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-0"
    }

    preview_path = "/tmp/preview.zip"
    extract_dir = "/tmp/extracted"
    app_path = "/tmp/extracted/MyApp.app"

    stub(Simulators, :devices, fn -> {:ok, [device]} end)

    stub(Briefly, :create, fn
      [extname: ".zip"] -> {:ok, preview_path}
      [directory: true] -> {:ok, extract_dir}
      [] -> {:ok, "/tmp/recording.mp4"}
      [extname: ".mp4"] -> {:ok, "/tmp/recording_fixed.mp4"}
    end)

    stub(File, :stream!, fn ^preview_path -> :mocked_stream end)
    stub(Runner.Zip, :extract, fn _, _ -> {:ok, []} end)
    stub(File, :ls, fn ^extract_dir -> {:ok, ["MyApp.app"]} end)

    stub(Simulators, :boot_simulator, fn ^device -> :ok end)
    stub(Simulators, :install_app, fn ^app_path, ^device -> :ok end)
    stub(Simulators, :launch_app, fn _bundle_identifier, ^device, _launch_arguments -> :ok end)

    stub(AppiumClient, :start_session, fn _, _ -> {:ok, %{id: "mock-session"}} end)
    stub(AppiumClient, :stop_session, fn _ -> :ok end)

    stub(ChatAnthropic, :new!, fn _ ->
      %ChatAnthropic{api_key: "test-api-key", model: "claude-sonnet-4-20250514"}
    end)

    stub(LLMChain, :new!, fn %{llm: llm} ->
      %LLMChain{llm: llm, messages: [], last_message: nil}
    end)

    stub(LLMChain, :add_messages, fn chain, _messages -> chain end)
    stub(LLMChain, :add_tools, fn chain, _ -> chain end)
    stub(LLMChain, :add_callback, fn chain, _ -> chain end)
    stub(LLMChain, :run, fn chain, _opts -> {:ok, chain} end)

    stub(Tools, :tools, fn _params ->
      [
        %{name: "describe_ui"},
        %{name: "tap"},
        %{name: "long_press"},
        %{name: "swipe"},
        %{name: "type_text"},
        %{name: "key_press"},
        %{name: "button"},
        %{name: "touch"},
        %{name: "gesture"},
        %{name: "screenshot"},
        %{name: "step_report"},
        %{name: "finalize"}
      ]
    end)

    stub(Client, :start_run, fn %{
                                  server_url: _server_url,
                                  run_id: _run_id,
                                  auth_token: _auth_token,
                                  account_handle: _account_handle,
                                  project_handle: _project_handle
                                } ->
      {:ok, "started"}
    end)

    stub(Client, :start_log_stream, fn %{
                                         server_url: _server_url,
                                         run_id: _run_id,
                                         auth_token: _auth_token
                                       } ->
      {:ok, :fake_log_streamer_pid}
    end)

    stub(Client, :stream_log, fn :fake_log_streamer_pid, _log_params -> :ok end)

    stub(Sleeper, :sleep, fn _milliseconds -> :ok end)

    {:ok, device: device, preview_path: preview_path, extract_dir: extract_dir, app_path: app_path}
  end

  describe "test/1" do
    test "successfully runs QA test with action tools", %{
      device: device
    } do
      # Given
      preview_url = "https://example.com/preview.zip"
      bundle_identifier = "com.example.app"
      prompt = "Test the login feature"
      recording_port = 12_345

      expect(Req, :get, fn ^preview_url, [into: :mocked_stream] -> {:ok, %{status: 200}} end)
      expect(Simulators, :launch_app, fn ^bundle_identifier, ^device, _launch_arguments -> :ok end)

      expect(LLMChain, :run_until_tool_used, fn _chain, _tool_names, _opts ->
        {:ok, %LLMChain{}, %ToolResult{name: "plan_report", content: ["Test plan created"]}}
      end)

      expect(Simulators, :start_recording, fn _device_arg, _recording_path_arg ->
        recording_port
      end)

      expect(LLMChain, :run_until_tool_used, fn _chain, _tool_names, _opts ->
        {:ok, %LLMChain{}, %ToolResult{name: "tap", content: ["Tapped on element"]}}
      end)

      expect(LLMChain, :run_until_tool_used, fn _chain, _tool_names, _opts ->
        {:ok, %LLMChain{}, %ToolResult{name: "finalize", content: ["Test completed successfully"]}}
      end)

      expect(Simulators, :stop_recording, fn ^recording_port -> :ok end)

      expect(System, :cmd, fn "ffprobe", _args ->
        {~s({"format": {"duration": "30.0"}}), 0}
      end)

      expect(System, :cmd, fn "ffmpeg", _args ->
        {"", 0}
      end)

      expect(Client, :upload_recording, fn _params ->
        {:ok, %{upload_id: "upload-123", storage_key: "test-key"}}
      end)

      # When / Then
      result =
        Agent.test(
          %{
            preview_url: preview_url,
            bundle_identifier: bundle_identifier,
            prompt: prompt,
            server_url: "https://example.com",
            run_id: "run-id",
            auth_token: "auth-token",
            account_handle: "test-account",
            project_handle: "test-project"
          },
          anthropic_api_key: "api_key"
        )

      assert result == :ok
    end

    test "successfully runs QA test without action tools (no recording upload)", %{
      device: device
    } do
      # Given
      preview_url = "https://example.com/preview.zip"
      bundle_identifier = "com.example.app"
      prompt = "Check if app launches"
      recording_port = 12_345

      expect(Req, :get, fn ^preview_url, [into: :mocked_stream] -> {:ok, %{status: 200}} end)
      expect(Simulators, :launch_app, fn ^bundle_identifier, ^device, _launch_arguments -> :ok end)

      expect(LLMChain, :run_until_tool_used, fn _chain, _tool_names, _opts ->
        {:ok, %LLMChain{}, %ToolResult{name: "plan_report", content: ["Test plan created"]}}
      end)

      expect(Simulators, :start_recording, fn _device_arg, _recording_path_arg ->
        recording_port
      end)

      expect(LLMChain, :run_until_tool_used, fn _chain, _tool_names, _opts ->
        {:ok, %LLMChain{}, %ToolResult{name: "finalize", content: ["Test completed successfully"]}}
      end)

      expect(Simulators, :stop_recording, fn ^recording_port -> :ok end)

      # When / Then
      result =
        Agent.test(
          %{
            preview_url: preview_url,
            bundle_identifier: bundle_identifier,
            prompt: prompt,
            server_url: "https://example.com",
            run_id: "run-id",
            auth_token: "auth-token",
            account_handle: "test-account",
            project_handle: "test-project"
          },
          anthropic_api_key: "api_key"
        )

      assert result == :ok
    end

    test "returns error when simulator device cannot be found" do
      # Given
      expect(Simulators, :devices, fn -> {:ok, []} end)

      # When / Then
      assert {:error, "No iOS simulator found"} =
               Agent.test(
                 %{
                   preview_url: "https://example.com/preview.zip",
                   bundle_identifier: "com.example.app",
                   prompt: "Test feature",
                   server_url: "https://example.com",
                   run_id: "run-id",
                   auth_token: "auth-token",
                   account_handle: "test-account",
                   project_handle: "test-project"
                 },
                 anthropic_api_key: "api_key"
               )
    end

    test "returns error when preview download fails" do
      # Given
      expect(Briefly, :create, fn [extname: ".zip"] -> {:ok, "/tmp/preview.zip"} end)
      expect(Req, :get, fn _, [into: :mocked_stream] -> {:error, :econnrefused} end)

      # When / Then
      assert {:error, "Failed to download preview: econnrefused"} =
               Agent.test(
                 %{
                   preview_url: "https://example.com/invalid.zip",
                   bundle_identifier: "com.example.app",
                   prompt: "Test feature",
                   server_url: "https://example.com",
                   run_id: "run-id",
                   auth_token: "auth-token",
                   account_handle: "test-account",
                   project_handle: "test-project"
                 },
                 anthropic_api_key: "api_key"
               )
    end

    test "returns error when app extraction fails", %{extract_dir: extract_dir} do
      # Given
      expect(Req, :get, fn _, [into: :mocked_stream] -> {:ok, %{status: 200}} end)
      expect(File, :ls, fn ^extract_dir -> {:ok, []} end)

      # When / Then
      assert {:error, "No .app bundle found in the preview"} =
               Agent.test(
                 %{
                   preview_url: "https://example.com/preview.zip",
                   bundle_identifier: "com.example.app",
                   prompt: "Test feature",
                   server_url: "https://example.com",
                   run_id: "run-id",
                   auth_token: "auth-token",
                   account_handle: "test-account",
                   project_handle: "test-project"
                 },
                 anthropic_api_key: "api_key"
               )
    end

    test "clears previous UI and screenshot content when tool result contains UI/screenshot data and uploads recording",
         %{
           device: device
         } do
      # Given
      preview_url = "https://example.com/preview.zip"
      bundle_identifier = "com.example.app"

      messages = [
        %Message{
          role: :user,
          content: [%{type: :text, content: "Test the app"}]
        },
        %Message{
          role: :assistant,
          tool_calls: [%{name: "tap", call_id: "tap_id", arguments: %{}}]
        },
        %Message{
          role: :tool,
          tool_results: [
            %ToolResult{
              name: "tap",
              tool_call_id: "tap_id",
              content: [
                "Previous tap result",
                ContentPart.text!(~s({"AppiumAUT": {"UI": "data"}})),
                ContentPart.image!("image_data", media: :png)
              ]
            }
          ]
        },
        %Message{
          role: :assistant,
          tool_calls: [%{name: "describe_ui", call_id: "describe_ui_id", arguments: %{}}]
        },
        %Message{
          role: :tool,
          tool_results: [
            %ToolResult{
              name: "describe_ui",
              tool_call_id: "describe_ui_id",
              content: [ContentPart.text!(~s({"AppiumAUT": {"UI": "data"}}))]
            }
          ]
        },
        %Message{
          role: :assistant,
          tool_calls: [%{name: "swipe", call_id: "swipe_one_id", arguments: %{}}]
        },
        %Message{
          role: :tool,
          tool_results: [
            %ToolResult{name: "swipe", tool_call_id: "swipe_one_id", content: ["Swipe data"]}
          ]
        },
        %Message{role: :assistant, content: [%{type: :text, content: "Continuing test"}]}
      ]

      expect(Req, :get, fn ^preview_url, [into: :mocked_stream] -> {:ok, %{status: 200}} end)

      expect(Simulators, :launch_app, fn ^bundle_identifier, ^device, _launch_arguments -> :ok end)

      expect(LLMChain, :new!, 1, fn %{llm: llm} ->
        %LLMChain{llm: llm, messages: [], last_message: nil}
      end)

      expect(LLMChain, :add_messages, 1, fn chain, [user_msg] ->
        %{chain | messages: [user_msg]}
      end)

      expect(LLMChain, :run_until_tool_used, 1, fn input_chain, _tool_names, _opts ->
        chain_with_messages = %{
          input_chain
          | messages: messages,
            last_message: %Message{
              role: :assistant,
              content: [%{type: :text, content: "New action"}]
            }
        }

        {:ok, chain_with_messages,
         %ToolResult{
           name: "tap",
           content: [
             ContentPart.text!(~s({"AppiumAUT": {"UI": "New data"}})),
             ContentPart.image!("screenshot_data", media: :png)
           ]
         }}
      end)

      expect(LLMChain, :new!, 1, fn %{llm: llm} ->
        %LLMChain{llm: llm, messages: [], last_message: nil}
      end)

      expect(LLMChain, :add_messages, 1, fn chain, cleared_messages ->
        assert cleared_messages == [
                 %Message{
                   role: :user,
                   content: [%{type: :text, content: "Test the app"}],
                   tool_calls: [],
                   tool_results: []
                 },
                 %Message{
                   role: :assistant,
                   tool_calls: [%{name: "tap", call_id: "tap_id", arguments: %{}}],
                   tool_results: []
                 },
                 %Message{
                   role: :tool,
                   content: nil,
                   tool_results: [
                     %ToolResult{
                       name: "tap",
                       tool_call_id: "tap_id",
                       content: ["Previous tap result"]
                     }
                   ],
                   tool_calls: []
                 },
                 %Message{
                   role: :assistant,
                   tool_calls: [%{name: "swipe", call_id: "swipe_one_id", arguments: %{}}],
                   tool_results: []
                 },
                 %Message{
                   role: :tool,
                   tool_results: [
                     %ToolResult{
                       name: "swipe",
                       tool_call_id: "swipe_one_id",
                       content: ["Swipe data"]
                     }
                   ],
                   tool_calls: []
                 },
                 %Message{
                   role: :assistant,
                   content: [%{type: :text, content: "Continuing test"}],
                   tool_calls: nil,
                   tool_results: nil
                 }
               ]

        %{chain | messages: cleared_messages}
      end)

      expect(LLMChain, :run_until_tool_used, 1, fn chain, _tool_names, _opts ->
        {:ok, chain, %ToolResult{name: "plan_report", content: ["Test plan created"]}}
      end)

      expect(Simulators, :start_recording, fn _device_arg, _recording_path_arg ->
        12_345
      end)

      expect(LLMChain, :new!, 1, fn attrs ->
        %LLMChain{llm: attrs.llm, messages: [], last_message: nil}
      end)

      expect(LLMChain, :add_messages, 1, fn chain, _messages -> chain end)
      expect(LLMChain, :add_tools, 1, fn chain, _tools -> chain end)
      expect(LLMChain, :add_callback, 1, fn chain, _handler -> chain end)

      expect(LLMChain, :run_until_tool_used, 1, fn chain, _tool_names, _opts ->
        {:ok, chain, %ToolResult{name: "finalize", content: ["Test completed"]}}
      end)

      expect(Simulators, :stop_recording, fn 12_345 -> :ok end)

      expect(System, :cmd, fn "ffprobe", _args ->
        {~s({"format": {"duration": "30.0"}}), 0}
      end)

      expect(System, :cmd, fn "ffmpeg", _args ->
        {"", 0}
      end)

      expect(Client, :upload_recording, fn _params ->
        {:ok, %{upload_id: "upload-123", storage_key: "test-key"}}
      end)

      # When / Then
      assert :ok =
               Agent.test(
                 %{
                   preview_url: preview_url,
                   bundle_identifier: bundle_identifier,
                   prompt: "Test feature",
                   server_url: "https://example.com",
                   run_id: "run-id",
                   auth_token: "auth-token",
                   account_handle: "test-account",
                   project_handle: "test-project"
                 },
                 anthropic_api_key: "api_key"
               )
    end

    test "calls run_until_tool_used with step_report when an action tool is called", %{
      device: device
    } do
      # Given
      preview_url = "https://example.com/preview.zip"
      bundle_identifier = "com.example.app"
      prompt = "Test the login feature"

      expect(Req, :get, fn ^preview_url, [into: :mocked_stream] -> {:ok, %{status: 200}} end)

      expect(Simulators, :launch_app, fn ^bundle_identifier, ^device, _launch_arguments -> :ok end)

      expect(LLMChain, :new!, 1, fn %{llm: llm} ->
        %LLMChain{llm: llm, messages: [], last_message: nil}
      end)

      expect(LLMChain, :add_messages, 1, fn chain, [user_msg] ->
        %{chain | messages: [user_msg]}
      end)

      expect(LLMChain, :run_until_tool_used, 1, fn chain, _tool_names, _opts ->
        {:ok,
         %{
           chain
           | messages: [
               %Message{
                 role: :user,
                 content: [%{type: :text, content: "Test the login feature"}]
               },
               %Message{
                 role: :assistant,
                 tool_calls: [%{name: "tap", call_id: "tap_1", arguments: %{}}]
               },
               %Message{
                 role: :tool,
                 tool_results: [
                   %ToolResult{
                     name: "tap",
                     tool_call_id: "tap_1",
                     content: [
                       ContentPart.text!("Tapped element"),
                       ContentPart.image!("screenshot_data", media: :png),
                       ContentPart.text!("step_123")
                     ]
                   }
                 ]
               }
             ],
             last_message: %Message{
               role: :tool,
               tool_results: [
                 %ToolResult{
                   name: "tap",
                   tool_call_id: "tap_1",
                   content: [
                     ContentPart.text!("Tapped element"),
                     ContentPart.image!("screenshot_data", media: :png),
                     ContentPart.text!("step_123")
                   ]
                 }
               ]
             }
         },
         %ToolResult{
           name: "tap",
           content: [
             ContentPart.text!("Tapped element"),
             ContentPart.image!("screenshot_data", media: :png),
             ContentPart.text!("step_123")
           ]
         }}
      end)

      expect(LLMChain, :new!, 1, fn %{llm: llm} ->
        %LLMChain{llm: llm, messages: [], last_message: nil}
      end)

      expect(LLMChain, :add_messages, 1, fn chain, messages ->
        assert List.last(messages) ==
                 Message.new_user!(
                   "Use the returned image to analyze visual inconsistencies and report the result for step_id step_123 with the step_report tool."
                 )

        %{chain | messages: messages}
      end)

      expect(LLMChain, :run, 1, fn chain, [mode: :until_success] ->
        {:ok, chain}
      end)

      expect(LLMChain, :new!, 1, fn %{llm: llm} ->
        %LLMChain{llm: llm, messages: [], last_message: nil}
      end)

      expect(LLMChain, :add_messages, 1, fn chain, _messages ->
        %{chain | messages: []}
      end)

      expect(LLMChain, :run_until_tool_used, 1, fn chain, _tool_names, _opts ->
        {:ok, chain, %ToolResult{name: "plan_report", content: ["Test plan created"]}}
      end)

      expect(Simulators, :start_recording, fn _device_arg, _recording_path_arg ->
        12_345
      end)

      expect(LLMChain, :new!, 1, fn attrs ->
        %LLMChain{llm: attrs.llm, messages: [], last_message: nil}
      end)

      expect(LLMChain, :add_messages, 1, fn chain, _messages -> chain end)
      expect(LLMChain, :add_tools, 1, fn chain, _tools -> chain end)
      expect(LLMChain, :add_callback, 1, fn chain, _handler -> chain end)

      expect(LLMChain, :run_until_tool_used, 1, fn chain, _tool_names, _opts ->
        {:ok, chain, %ToolResult{name: "finalize", content: ["Test completed"]}}
      end)

      expect(Simulators, :stop_recording, fn 12_345 -> :ok end)

      expect(System, :cmd, fn "ffprobe", _args ->
        {~s({"format": {"duration": "30.0"}}), 0}
      end)

      expect(System, :cmd, fn "ffmpeg", _args ->
        {"", 0}
      end)

      expect(Client, :upload_recording, fn _params ->
        {:ok, %{upload_id: "upload-123", storage_key: "test-key"}}
      end)

      # When / Then
      assert :ok =
               Agent.test(
                 %{
                   preview_url: preview_url,
                   bundle_identifier: bundle_identifier,
                   prompt: prompt,
                   server_url: "https://example.com",
                   run_id: "run-id",
                   auth_token: "auth-token",
                   account_handle: "test-account",
                   project_handle: "test-project"
                 },
                 anthropic_api_key: "api_key"
               )
    end
  end
end
