defmodule Runner.QA.Agent do
  @moduledoc """
  Tuist QA agent module.
  """

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Message
  alias LangChain.Message.ContentPart
  alias LangChain.TokenUsage
  alias Runner.QA.Client
  alias Runner.QA.Simulators
  alias Runner.QA.Tools
  alias Runner.Zip

  require Logger

  @claude_model "claude-sonnet-4-20250514"

  defp log_and_stream(data, log_streamer, type) do
    Logger.info(inspect(data))

    Client.stream_log(log_streamer, %{
      data: JSON.encode!(data),
      type: type,
      timestamp: DateTime.utc_now()
    })
  end

  def test(
        %{
          preview_url: preview_url,
          bundle_identifier: bundle_identifier,
          prompt: prompt,
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle
        },
        opts
      ) do
    anthropic_api_key = Keyword.get(opts, :anthropic_api_key)

    with {:ok, simulator_device} <- simulator_device(),
         :ok <- run_preview(preview_url, bundle_identifier, simulator_device),
         {:ok, _} <-
           Client.start_run(%{
             server_url: server_url,
             run_id: run_id,
             auth_token: auth_token,
             account_handle: account_handle,
             project_handle: project_handle
           }),
         {:ok, log_streamer} <-
           Client.start_log_stream(%{
             server_url: server_url,
             run_id: run_id,
             auth_token: auth_token
           }) do
      handler = %{
        on_message_processed: fn _chain,
                                 %Message{
                                   content: content,
                                   tool_calls: tool_calls,
                                   tool_results: tool_results
                                 } ->
          for %ContentPart{type: :text, content: text_content} <- content || [] do
            log_and_stream(%{message: text_content}, log_streamer, "message")
          end

          for tool_call <- tool_calls || [] do
            log_and_stream(
              %{
                name: tool_call.name,
                arguments: tool_call.arguments
              },
              log_streamer,
              "tool_call"
            )
          end

          for tool_result <- tool_results || [] do
            content_data =
              case tool_result.content do
                content_parts when is_list(content_parts) ->
                  Enum.map(content_parts, fn
                    %ContentPart{type: type, content: content} -> %{type: type, content: content}
                    other -> other
                  end)

                other ->
                  other
              end

            log_and_stream(
              %{
                name: tool_result.name,
                content: content_data
              },
              log_streamer,
              "tool_call_result"
            )
          end
        end,
        on_llm_token_usage: fn _chain, %TokenUsage{input: input, output: output} ->
          log_and_stream(
            %{
              input: input,
              output: output,
              model: @claude_model
            },
            log_streamer,
            "usage"
          )
        end
      }

      prompt = """
      You are a QA agent. Test the following: #{prompt}.

      First, understand what you need to test. Then, set up a plan to test the feature and execute on it without asking for additional instructions. Take screenshots to analyze whether there are any visual inconsistencies.

      When using tools, use the following udid: #{simulator_device.udid}.

      When interacting with the app:
      - Prefer using describe_ui over screenshot to interact with the app
      - To dismiss a system sheet, tap within the visible screen area but outside the sheet, such in the dark/grayed area above the sheet
      - If a button includes text, prefer tapping on the text to interact with the button
      - To clear fields, use the 42 keycode (backspace) with a longer duration
      - Don't clear pre-filled/placeholder values in fields – instead start typing the text directly
      """

      llm =
        ChatAnthropic.new!(%{
          model: @claude_model,
          max_tokens: 2000,
          api_key: anthropic_api_key
        })

      tools =
        Tools.tools(%{
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle
        })

      case run_llm(%{llm: llm, max_retry_count: 10}, handler, [Message.new_user!(prompt)], tools) do
        {:error, error_message} ->
          log_and_stream(%{message: error_message}, log_streamer, "message")

          Client.fail_run(%{
            error_message: error_message,
            server_url: server_url,
            run_id: run_id,
            auth_token: auth_token,
            account_handle: account_handle,
            project_handle: project_handle
          })

          {:error, error_message}

        result ->
          result
      end
    end
  end

  defp run_llm(attrs, handler, messages, tools) do
    attrs
    |> LLMChain.new!()
    |> LLMChain.add_messages(messages)
    |> LLMChain.add_tools(tools)
    |> LLMChain.add_callback(handler)
    |> LLMChain.run_until_tool_used(["describe_ui", "screenshot", "finalize"])
    |> process_llm_result(attrs, handler, tools)
  end

  defp process_llm_result({:ok, %LLMChain{last_message: last_message} = chain, tool_result}, attrs, handler, tools) do
    case tool_result.name do
      tool_name when tool_name in ["describe_ui", "screenshot"] ->
        trimmed_messages = trim_tool_messages(Enum.drop(chain.messages, -1), tool_name)
        run_llm(attrs, handler, trimmed_messages ++ [last_message], tools)

      "finalize" ->
        :ok
    end
  end

  defp process_llm_result({:error, _chain, %LangChain.LangChainError{message: message}}, _attrs, _handler, _tools) do
    {:error, "LLM chain execution failed: #{message}"}
  end

  defp trim_tool_messages(messages, tool_name) do
    messages
    |> Enum.with_index()
    |> Enum.reject(fn {message, index} ->
      # Check if this is a tool result message with the specified tool
      if has_message_tool_result_with_name(message, tool_name) do
        true
      else
        next_message = Enum.at(messages, index + 1)

        # Check if the next message (if exists) is a tool result with the specified tool
        # If so, and this message has the corresponding tool_call, remove it too
        next_message && has_message_tool_result_with_name(next_message, tool_name) &&
          has_message_tool_call_with_name(message, tool_name)
      end
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp has_message_tool_call_with_name(message, tool_name) do
    Enum.any?(message.tool_calls || [], fn tool_call ->
      tool_call.name == tool_name
    end)
  end

  defp has_message_tool_result_with_name(message, tool_name) do
    Enum.any?(message.tool_results || [], fn tool_result ->
      tool_result.name == tool_name
    end)
  end

  defp run_preview(preview_url, bundle_identifier, simulator_device) do
    with {:ok, preview_path} <- download_preview(preview_url),
         {:ok, app_path} <- extract_app_from_preview(preview_path, bundle_identifier),
         :ok <- Simulators.boot_simulator(simulator_device),
         :ok <- Simulators.install_app(app_path, simulator_device) do
      Simulators.launch_app(bundle_identifier, simulator_device)
    end
  end

  defp simulator_device do
    case Simulators.devices() do
      {:ok, devices} ->
        device =
          Enum.find(devices, fn device ->
            device.name == "iPhone 16" and
              device.runtime_identifier == "com.apple.CoreSimulator.SimRuntime.iOS-18-5"
          end)

        case device do
          nil -> {:error, "No iOS simulator found"}
          device -> {:ok, device}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp download_preview(preview_url) do
    with {:ok, preview_path} <- Briefly.create(extname: ".zip"),
         {:ok, _response} <- Req.get(preview_url, into: File.stream!(preview_path)) do
      {:ok, preview_path}
    else
      {:error, reason} ->
        {:error, "Failed to download preview: #{reason}"}
    end
  end

  defp extract_app_from_preview(preview_path, _bundle_identifier) do
    with {:ok, extract_dir} <- Briefly.create(directory: true),
         {:ok, _extracted_files} <-
           Zip.extract(String.to_charlist(preview_path), [{:cwd, String.to_charlist(extract_dir)}]),
         {:ok, files} <- File.ls(extract_dir),
         app_name when not is_nil(app_name) <- Enum.find(files, &String.ends_with?(&1, ".app")) do
      {:ok, Path.join(extract_dir, app_name)}
    else
      {:error, reason} ->
        {:error, "Failed to extract app from preview: #{reason}"}

      nil ->
        {:error, "No .app bundle found in the preview"}
    end
  end
end
