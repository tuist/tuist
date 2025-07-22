defmodule Tuist.QA.AgentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Message
  alias LangChain.Message.ToolResult
  alias Tuist.QA.Agent
  alias Tuist.QA.Tools
  alias Tuist.Simulators.SimulatorDevice

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

    stub(Tuist.Simulators, :devices, fn -> {:ok, [device]} end)

    stub(Briefly, :create, fn
      [extname: ".zip"] -> {:ok, preview_path}
      [directory: true] -> {:ok, extract_dir}
    end)

    stub(File, :stream!, fn ^preview_path -> :mocked_stream end)
    stub(Tuist.Zip, :extract, fn _, _ -> {:ok, []} end)
    stub(File, :ls, fn ^extract_dir -> {:ok, ["MyApp.app"]} end)

    stub(Tuist.Simulators, :boot_simulator, fn ^device -> :ok end)
    stub(Tuist.Simulators, :install_app, fn ^app_path, ^device -> :ok end)

    stub(Tuist.Environment, :anthropic_api_key, fn -> "test-api-key" end)
    stub(ChatAnthropic, :new!, fn _ -> %ChatAnthropic{api_key: "test-api-key", model: "claude-sonnet-4-20250514"} end)

    stub(LLMChain, :new!, fn llm -> %LLMChain{llm: llm, messages: [], last_message: nil} end)
    stub(LLMChain, :add_messages, fn chain, _messages -> chain end)
    stub(LLMChain, :add_tools, fn chain, _ -> chain end)
    stub(LLMChain, :add_callback, fn chain, _ -> chain end)

    stub(Tools, :tools, fn -> [] end)

    {:ok, device: device, preview_path: preview_path, extract_dir: extract_dir, app_path: app_path}
  end

  describe "test/1" do
    test "successfully runs QA test", %{device: device} do
      # Given
      preview_url = "https://example.com/preview.zip"
      bundle_identifier = "com.example.app"
      prompt = "Test the login feature"

      expect(Req, :get, fn ^preview_url, [into: :mocked_stream] -> {:ok, %{status: 200}} end)
      expect(Tuist.Simulators, :launch_app, fn ^bundle_identifier, ^device -> :ok end)

      expect(LLMChain, :new!, fn llm ->
        %LLMChain{
          llm: llm,
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
      end)

      expect(LLMChain, :run_until_tool_used, fn chain, _ ->
        {:ok, chain, %ToolResult{name: "finalize", content: ["Test completed successfully"]}}
      end)

      # When / Then
      assert :ok =
               Agent.test(%{
                 preview_url: preview_url,
                 bundle_identifier: bundle_identifier,
                 prompt: prompt
               })
    end

    test "returns error when simulator device cannot be found" do
      # Given
      expect(Tuist.Simulators, :devices, fn -> {:ok, []} end)

      # When / Then
      assert {:error, "No iOS simulator found"} =
               Agent.test(%{
                 preview_url: "https://example.com/preview.zip",
                 bundle_identifier: "com.example.app",
                 prompt: "Test feature"
               })
    end

    test "returns error when preview download fails" do
      # Given
      expect(Briefly, :create, fn [extname: ".zip"] -> {:ok, "/tmp/preview.zip"} end)
      expect(Req, :get, fn _, [into: :mocked_stream] -> {:error, :econnrefused} end)

      # When / Then
      assert {:error, "Failed to download preview: econnrefused"} =
               Agent.test(%{
                 preview_url: "https://example.com/invalid.zip",
                 bundle_identifier: "com.example.app",
                 prompt: "Test feature"
               })
    end

    test "returns error when app extraction fails", %{extract_dir: extract_dir} do
      # Given
      expect(Req, :get, fn _, [into: :mocked_stream] -> {:ok, %{status: 200}} end)
      expect(File, :ls, fn ^extract_dir -> {:ok, []} end)

      # When / Then
      assert {:error, "No .app bundle found in the preview"} =
               Agent.test(%{
                 preview_url: "https://example.com/preview.zip",
                 bundle_identifier: "com.example.app",
                 prompt: "Test feature"
               })
    end

    test "trims previous describe_ui and screenshot tool calls from message history", %{device: device} do
      # Given
      preview_url = "https://example.com/preview.zip"
      bundle_identifier = "com.example.app"

      messages = [
        %Message{role: :user, content: [%{type: :text, content: "Test the app"}]},
        %Message{
          role: :assistant,
          tool_calls: [%{name: "describe_ui", arguments: %{}}]
        },
        %Message{
          role: :tool,
          tool_results: [%ToolResult{name: "describe_ui", content: ["UI hierarchy"]}]
        },
        %Message{
          role: :assistant,
          tool_calls: [%{name: "screenshot", arguments: %{}}]
        },
        %Message{
          role: :tool,
          tool_results: [%ToolResult{name: "screenshot", content: ["Screenshot data"]}]
        },
        %Message{role: :assistant, content: [%{type: :text, content: "Continuing test"}]}
      ]

      expect(Req, :get, fn ^preview_url, [into: :mocked_stream] -> {:ok, %{status: 200}} end)
      expect(Tuist.Simulators, :launch_app, fn ^bundle_identifier, ^device -> :ok end)

      expect(LLMChain, :new!, 1, fn llm -> %LLMChain{llm: llm, messages: [], last_message: nil} end)

      expect(LLMChain, :add_messages, 1, fn chain, [user_msg] ->
        %{chain | messages: [user_msg]}
      end)

      expect(LLMChain, :run_until_tool_used, 1, fn input_chain, ["describe_ui", "screenshot", "finalize"] ->
        chain_with_messages = %{
          input_chain
          | messages: messages,
            last_message: %Message{
              role: :assistant,
              content: [%{type: :text, content: "New action"}]
            }
        }

        {:ok, chain_with_messages, %ToolResult{name: "describe_ui", content: ["New UI data"]}}
      end)

      expect(LLMChain, :new!, 1, fn llm -> %LLMChain{llm: llm, messages: [], last_message: nil} end)

      # previous describe_ui tool calls are removed
      expect(LLMChain, :add_messages, 1, fn chain, messages ->
        assert Enum.map(messages, &Map.take(&1, [:role, :content, :tool_calls, :tool_results])) == [
                 %{content: [%{content: "Test the app", type: :text}], role: :user, tool_calls: nil, tool_results: nil},
                 %{
                   role: :assistant,
                   tool_calls: [%{arguments: %{}, name: "screenshot"}],
                   content: nil,
                   tool_results: nil
                 },
                 %{
                   role: :tool,
                   tool_results: [
                     %LangChain.Message.ToolResult{
                       content: ["Screenshot data"],
                       name: "screenshot"
                     }
                   ],
                   content: nil,
                   tool_calls: nil
                 },
                 %{content: [%{content: "New action", type: :text}], role: :assistant, tool_calls: nil, tool_results: nil}
               ]

        %{chain | messages: messages}
      end)

      expect(LLMChain, :run_until_tool_used, 1, fn chain, ["describe_ui", "screenshot", "finalize"] ->
        {:ok, chain, %ToolResult{name: "finalize", content: ["Test completed"]}}
      end)

      # When / Then
      assert :ok =
               Agent.test(%{
                 preview_url: preview_url,
                 bundle_identifier: bundle_identifier,
                 prompt: "Test feature"
               })
    end
  end
end
