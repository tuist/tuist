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
        %{name: "describe_ui"}, %{name: "tap"}, %{name: "long_press"},
        %{name: "swipe"}, %{name: "type_text"}, %{name: "key_press"}, 
        %{name: "button"}, %{name: "touch"}, %{name: "gesture"}, 
        %{name: "screenshot"}, %{name: "step_report"}, %{name: "finalize"}
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

      expect(LLMChain, :run_until_tool_used, fn _chain, tool_names ->
        # Should be all tool names except step_report
        refute "step_report" in tool_names
        assert "finalize" in tool_names
        assert "describe_ui" in tool_names
        assert "screenshot" in tool_names
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

    test "clears previous UI and screenshot content when tool result contains UI/screenshot data", %{
      device: device
    } do
      # Given
      preview_url = "https://example.com/preview.zip"
      bundle_identifier = "com.example.app"

      messages = [
        %Message{role: :user, content: [%{type: :text, content: "Test the app"}]},
        %Message{
          role: :assistant,
          tool_calls: [%{name: "tap", arguments: %{}}]
        },
        %Message{
          role: :tool,
          tool_results: [%ToolResult{name: "tap", content: ["Previous tap result"]}],
          content: [ContentPart.text!("Current UI state: UI data"), ContentPart.image!("image_data", media: :png)]
        },
        %Message{
          role: :tool,
          tool_results: [%ToolResult{name: "describe_ui", content: ["UI data"]}],
          content: [ContentPart.text!("Current UI state: More UI data"), ContentPart.image!("screenshot_data", media: :png)]
        },
        %Message{
          role: :assistant,
          tool_calls: [%{name: "swipe", arguments: %{}}]
        },
        %Message{
          role: :tool,
          tool_results: [%ToolResult{name: "swipe", content: ["Swipe data"]}]
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

      expect(LLMChain, :run_until_tool_used, 1, fn input_chain, tool_names ->
        # Verify all tools except step_report are included
        refute "step_report" in tool_names
        
        chain_with_messages = %{
          input_chain
          | messages: messages,
            last_message: %Message{
              role: :assistant,
              content: [%{type: :text, content: "New action"}]
            }
        }

        {:ok, chain_with_messages, %ToolResult{name: "tap", content: [ContentPart.text!("Current UI state: New data"), ContentPart.image!("screenshot_data", media: :png)]}}
      end)

      expect(LLMChain, :new!, 1, fn %{llm: llm} ->
        %LLMChain{llm: llm, messages: [], last_message: nil}
      end)

      # Previous UI state and screenshot content should be cleared when new tool result contains UI/screenshot data
      expect(LLMChain, :add_messages, 1, fn chain, cleared_messages ->
        # Check that UI state and screenshot content is removed from previous messages
        # and messages that become empty are completely removed
        
        user_message = Enum.at(cleared_messages, 0)
        assert user_message.role == :user
        assert user_message.content == [%{type: :text, content: "Test the app"}]
        
        # The message with only describe_ui tool results and UI content should be completely removed
        describe_ui_only_message = Enum.find(cleared_messages, fn msg -> 
          msg.role == :tool && 
          Enum.any?(msg.tool_results || [], fn tr -> tr.name == "describe_ui" end) &&
          Enum.all?(msg.tool_results || [], fn tr -> tr.name in ["describe_ui", "screenshot"] end)
        end)
        assert describe_ui_only_message == nil, "Message with only UI/screenshot content should be completely removed"
        
        # Tool message with mixed content should have UI content cleared but other content preserved
        mixed_tool_message = Enum.find(cleared_messages, fn msg ->
          msg.role == :tool &&
          Enum.any?(msg.tool_results || [], fn tr -> tr.name == "tap" end)
        end)
        
        if mixed_tool_message do
          # Should preserve non-describe_ui/screenshot tool results  
          preserved_results = Enum.reject(mixed_tool_message.tool_results || [], fn tr -> tr.name in ["describe_ui", "screenshot"] end)
          assert length(preserved_results) > 0  # Should have the tap result
          assert mixed_tool_message.content == []  # Current UI content and image cleared
        end
        
        %{chain | messages: cleared_messages}
      end)

      expect(LLMChain, :run_until_tool_used, 1, fn chain, tool_names ->
        refute "step_report" in tool_names
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

    test "does not clear messages when tool result contains no UI/screenshot data", %{
      device: device
    } do
      # Given  
      preview_url = "https://example.com/preview.zip"
      bundle_identifier = "com.example.app"

      messages = [
        %Message{role: :user, content: [%{type: :text, content: "Test the app"}]},
        %Message{
          role: :assistant,
          tool_calls: [%{name: "tap", arguments: %{}}]
        },
        %Message{
          role: :tool,
          tool_results: [%ToolResult{name: "tap", content: ["Previous tap result"]}],
          content: [ContentPart.text!("Current UI state: UI data")]
        }
      ]

      expect(Req, :get, fn ^preview_url, [into: :mocked_stream] -> {:ok, %{status: 200}} end)
      expect(Simulators, :launch_app, fn ^bundle_identifier, ^device -> :ok end)

      expect(LLMChain, :new!, 1, fn %{llm: llm} ->
        %LLMChain{llm: llm, messages: [], last_message: nil}
      end)

      expect(LLMChain, :add_messages, 1, fn chain, [user_msg] ->
        %{chain | messages: [user_msg]}
      end)

      expect(LLMChain, :run_until_tool_used, 1, fn input_chain, tool_names ->
        refute "step_report" in tool_names
        
        chain_with_messages = %{
          input_chain
          | messages: messages,
            last_message: %Message{
              role: :assistant,
              content: [%{type: :text, content: "New action"}]
            }
        }

        # Tool result with NO UI/screenshot content - should not trigger clearing
        {:ok, chain_with_messages, %ToolResult{name: "swipe", content: [ContentPart.text!("Swipe completed successfully")]}}
      end)

      expect(LLMChain, :new!, 1, fn %{llm: llm} ->
        %LLMChain{llm: llm, messages: [], last_message: nil}
      end)

      # Messages should NOT be cleared since tool result contains no UI/screenshot data
      expect(LLMChain, :add_messages, 1, fn chain, messages_passed ->
        # Should be the full chain.messages (which includes original + last_message from run_until_tool_used)
        # In non-clearing case, we pass chain.messages directly
        assert length(messages_passed) >= length(messages)
        
        # Original UI content should still be present (not cleared)
        tool_message = Enum.find(messages_passed, &(&1.role == :tool))
        if tool_message do
          assert Enum.any?(tool_message.content || [], fn
            %ContentPart{type: :text, content: content} -> String.starts_with?(content, "Current UI")
            _ -> false
          end)
        end
        
        %{chain | messages: messages_passed}
      end)

      expect(LLMChain, :run_until_tool_used, 1, fn chain, tool_names ->
        refute "step_report" in tool_names
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
  end

  describe "contains_ui_content?/1" do
    test "returns true when tool result contains UI content in content parts" do
      tool_result = %ToolResult{
        name: "describe_ui",
        content: [
          %ContentPart{type: :text, content: "Current UI state: some data"},
          %ContentPart{type: :image, options: [media: :png]}
        ]
      }

      assert Agent.contains_ui_content?(tool_result)
    end

    test "returns true when tool result contains UI content as binary string" do
      tool_result = %ToolResult{
        name: "describe_ui", 
        content: "Current UI state: some data"
      }

      assert Agent.contains_ui_content?(tool_result)
    end

    test "returns false when tool result contains only screenshot content" do
      tool_result = %ToolResult{
        name: "screenshot",
        content: [%ContentPart{type: :image, options: [media: :png]}]
      }

      refute Agent.contains_ui_content?(tool_result)
    end

    test "returns false when tool result contains no UI or screenshot content" do
      tool_result = %ToolResult{
        name: "tap",
        content: ["Tap completed successfully"]
      }

      refute Agent.contains_ui_content?(tool_result)
    end
  end

  describe "contains_screenshot_content?/1" do
    test "returns true when tool result contains screenshot content" do
      tool_result = %ToolResult{
        name: "screenshot",
        content: [
          %ContentPart{type: :image, options: [media: :png]},
          %ContentPart{type: :text, content: "Screenshot taken"}
        ]
      }

      assert Agent.contains_screenshot_content?(tool_result)
    end

    test "returns false when tool result contains only UI content" do
      tool_result = %ToolResult{
        name: "describe_ui",
        content: [%ContentPart{type: :text, content: "Current UI state: some data"}]
      }

      refute Agent.contains_screenshot_content?(tool_result)
    end

    test "returns false when tool result contains no UI or screenshot content" do
      tool_result = %ToolResult{
        name: "tap",
        content: ["Tap completed successfully"]
      }

      refute Agent.contains_screenshot_content?(tool_result)
    end
  end

end
