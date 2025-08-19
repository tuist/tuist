defmodule Runner.QA.AgentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Message
  alias LangChain.Message.ContentPart
  alias LangChain.Message.ToolResult
  alias Runner.QA.Agent
  alias Runner.QA.Client
  alias Runner.QA.Simulators
  alias Runner.QA.Simulators.SimulatorDevice
  alias Runner.QA.Tools

  setup do
    device = %SimulatorDevice{
      name: "iPhone 16",
      udid: "42172B88-9A53-46C8-B560-75609012CF0D",
      state: "Booted",
      runtime_identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-5"
    }

    preview_path = "/tmp/preview.zip"
    extract_dir = "/tmp/extracted"
    app_path = "/tmp/extracted/MyApp.app"

    stub(Simulators, :devices, fn -> {:ok, [device]} end)

    stub(Briefly, :create, fn
      [extname: ".zip"] -> {:ok, preview_path}
      [directory: true] -> {:ok, extract_dir}
    end)

    stub(File, :stream!, fn ^preview_path -> :mocked_stream end)
    stub(Runner.Zip, :extract, fn _, _ -> {:ok, []} end)
    stub(File, :ls, fn ^extract_dir -> {:ok, ["MyApp.app"]} end)

    stub(Simulators, :boot_simulator, fn ^device -> :ok end)
    stub(Simulators, :install_app, fn ^app_path, ^device -> :ok end)

    stub(ChatAnthropic, :new!, fn _ ->
      %ChatAnthropic{api_key: "test-api-key", model: "claude-sonnet-4-20250514"}
    end)

    stub(LLMChain, :new!, fn %{llm: llm} ->
      %LLMChain{llm: llm, messages: [], last_message: nil}
    end)

    stub(LLMChain, :add_messages, fn chain, _messages -> chain end)
    stub(LLMChain, :add_tools, fn chain, _ -> chain end)
    stub(LLMChain, :add_callback, fn chain, _ -> chain end)

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

    {:ok, device: device, preview_path: preview_path, extract_dir: extract_dir, app_path: app_path}
  end

  describe "test/1" do
    test "successfully runs QA test", %{device: device} do
      # Given
      preview_url = "https://example.com/preview.zip"
      bundle_identifier = "com.example.app"
      prompt = "Test the login feature"

      expect(Req, :get, fn ^preview_url, [into: :mocked_stream] -> {:ok, %{status: 200}} end)
      expect(Simulators, :launch_app, fn ^bundle_identifier, ^device -> :ok end)

      chain_result = %LLMChain{
        llm: %ChatAnthropic{api_key: "test-api-key", model: "claude-sonnet-4-20250514"},
        messages: [],
        last_message: %Message{
          role: :tool,
          tool_results: [
            %ToolResult{
              name: "finalize",
              content: ["Test completed successfully"]
            }
          ]
        }
      }

      expect(LLMChain, :new!, fn attrs -> %{chain_result | llm: attrs.llm} end)
      expect(LLMChain, :add_messages, fn chain, _messages -> chain end)
      expect(LLMChain, :add_tools, fn chain, _tools -> chain end)
      expect(LLMChain, :add_callback, fn chain, _handler -> chain end)

      expect(LLMChain, :run_until_tool_used, fn _chain, _tool_names ->
        {:ok, chain_result, %ToolResult{name: "finalize", content: ["Test completed successfully"]}}
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

    test "clears previous UI and screenshot content when tool result contains UI/screenshot data",
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
                ContentPart.text!("Current UI state: UI data"),
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
              content: [ContentPart.text!("Current UI state: UI data")]
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
      expect(Simulators, :launch_app, fn ^bundle_identifier, ^device -> :ok end)

      expect(LLMChain, :new!, 1, fn %{llm: llm} ->
        %LLMChain{llm: llm, messages: [], last_message: nil}
      end)

      expect(LLMChain, :add_messages, 1, fn chain, [user_msg] ->
        %{chain | messages: [user_msg]}
      end)

      expect(LLMChain, :run_until_tool_used, 1, fn input_chain, _tool_names ->
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
             ContentPart.text!("Current UI state: New data"),
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

      expect(LLMChain, :run_until_tool_used, 1, fn chain, _tool_names ->
        {:ok, chain, %ToolResult{name: "finalize", content: ["Test completed"]}}
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
      expect(Simulators, :launch_app, fn ^bundle_identifier, ^device -> :ok end)

      expect(LLMChain, :new!, 1, fn %{llm: llm} ->
        %LLMChain{llm: llm, messages: [], last_message: nil}
      end)

      expect(LLMChain, :add_messages, 1, fn chain, [user_msg] ->
        %{chain | messages: [user_msg]}
      end)

      expect(LLMChain, :run_until_tool_used, 1, fn chain, _tool_names ->
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

      expect(LLMChain, :run_until_tool_used, 1, fn chain, tool_name ->
        assert tool_name == "step_report"
        {:ok, chain, %ToolResult{name: "step_report", content: ["Step reported successfully"]}}
      end)

      expect(LLMChain, :new!, 1, fn %{llm: llm} ->
        %LLMChain{llm: llm, messages: [], last_message: nil}
      end)

      expect(LLMChain, :add_messages, 1, fn chain, _messages ->
        %{chain | messages: []}
      end)

      expect(LLMChain, :run_until_tool_used, 1, fn chain, _tool_names ->
        {:ok, chain, %ToolResult{name: "finalize", content: ["Test completed"]}}
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
