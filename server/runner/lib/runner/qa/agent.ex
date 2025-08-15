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

      When using tools, use the following udid: #{simulator_device.udid}. After using a tool that returns an image, analyze it for visual inconsistencies.

      When interacting with the app, make sure to follow the these guidelines:
      - Prefer using describe_ui over screenshot to interact with the app
      - Don't read labels from screenshots. Always read them from the UI description.
      - To dismiss a system sheet, tap within the visible screen area but outside the sheet, such in the dark/grayed area above the sheet
      - If a button includes text, prefer tapping on the text to interact with the button
      - When you recognize a placeholder/pre-filled fields, you should never try to clear the placeholder value as it won't work. Instead, replace the text directly with type_text tool.
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

      # Get all tool names except step_report_tool for run_until_tool_used
      tool_names_except_step_report = tools |> Enum.map(& &1.name) |> Enum.reject(&(&1 == "step_report"))

      case run_llm(
             %{llm: llm, max_retry_count: 10},
             handler,
             [Message.new_user!(prompt)],
             tools,
             tool_names_except_step_report
           ) do
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

  defp run_llm(attrs, handler, messages, tools, tool_names_except_step_report) do
    attrs
    |> LLMChain.new!()
    |> LLMChain.add_messages(messages)
    |> LLMChain.add_tools(tools)
    |> LLMChain.add_callback(handler)
    |> LLMChain.run_until_tool_used(tool_names_except_step_report)
    |> process_llm_result(attrs, handler, tools, tool_names_except_step_report)
  end

  defp process_llm_result(
         {:ok, %LLMChain{last_message: last_message} = chain, tool_result},
         attrs,
         handler,
         tools,
         tool_names_except_step_report
       ) do
    case tool_result.name do
      "finalize" ->
        :ok

      tool_name ->
        # Check if the tool result contains UI content or screenshot content
        should_clear_ui_content = contains_ui_content?(tool_result)
        should_clear_screenshot_content = contains_screenshot_content?(tool_result)

        messages_to_use =
          if should_clear_ui_content or should_clear_screenshot_content do
            cleared_messages =
              clear_ui_and_screenshot_messages(
                Enum.drop(chain.messages, -1),
                should_clear_ui_content,
                should_clear_screenshot_content
              )

            cleared_messages ++ [last_message]
          else
            chain.messages
          end

        messages_to_use =
          if tool_name in ["tap", "swipe", "long_press", "type_text", "key_press", "button", "touch", "gesture"] do
            # Extract step_id and drop the last content item from the last tool_result
            {cleaned_messages, step_id} =
              case List.last(last_message.tool_results) do
                %{content: content_parts} = last_tool_result when is_list(content_parts) ->
                  # Get the step_id from the last content part
                  step_id =
                    case List.last(content_parts) do
                      %ContentPart{type: :text, content: text_content} -> text_content
                      _ -> nil
                    end

                  # Drop the last content part (step_id)
                  updated_tool_result = %{last_tool_result | content: Enum.drop(content_parts, -1)}

                  # Update the last message with the cleaned tool result
                  other_tool_results = Enum.drop(last_message.tool_results, -1)
                  updated_last_message = %{last_message | tool_results: other_tool_results ++ [updated_tool_result]}

                  # Replace the last message in messages_to_use
                  {Enum.drop(messages_to_use, -1) ++ [updated_last_message], step_id}

                _ ->
                  {messages_to_use, nil}
              end

            {:ok, chain, _} =
              attrs
              |> LLMChain.new!()
              |> LLMChain.add_messages(
                cleaned_messages ++
                  [
                    Message.new_user!(
                      "Use the returned image to analyze visual inconsistencies and report the result for step_id #{step_id} with the step_report tool."
                    )
                  ]
              )
              |> LLMChain.add_tools(tools)
              |> LLMChain.add_callback(handler)
              |> LLMChain.run_until_tool_used("step_report")

            chain.messages
          else
            messages_to_use
          end

        run_llm(attrs, handler, messages_to_use, tools, tool_names_except_step_report)
    end
  end

  defp process_llm_result(
         {:error, _chain, %LangChain.LangChainError{message: message}},
         _attrs,
         _handler,
         _tools,
         _tool_names_except_step_report
       ) do
    {:error, "LLM chain execution failed: #{message}"}
  end

  @doc false
  def contains_ui_content?(tool_result) do
    case tool_result.content do
      content_parts when is_list(content_parts) ->
        Enum.any?(content_parts, fn
          %ContentPart{type: :text, content: text_content} ->
            # Check for describe_ui content (text starting with "Current UI")
            String.starts_with?(text_content, "Current UI")

          _ ->
            false
        end)

      other when is_binary(other) ->
        # Handle string content that might start with "Current UI"
        String.starts_with?(other, "Current UI")

      _ ->
        false
    end
  end

  @doc false
  def contains_screenshot_content?(tool_result) do
    case tool_result.content do
      content_parts when is_list(content_parts) ->
        Enum.any?(content_parts, fn
          %ContentPart{type: :image, options: options} ->
            # Check for screenshot content (images with media: :png)
            Keyword.get(options || [], :media) == :png

          _ ->
            false
        end)

      _ ->
        false
    end
  end

  defp clear_ui_and_screenshot_messages(messages, clear_ui_content, clear_screenshot_content) do
    # First pass: identify which tool_results will be removed
    tools_to_clear = []
    tools_to_clear = if clear_ui_content, do: ["describe_ui" | tools_to_clear], else: tools_to_clear
    tools_to_clear = if clear_screenshot_content, do: ["screenshot" | tools_to_clear], else: tools_to_clear

    tool_results_to_remove =
      messages
      |> Enum.flat_map(fn message ->
        case message.tool_results do
          tool_results when is_list(tool_results) ->
            tool_results
            |> Enum.filter(fn tool_result ->
              # Remove if tool name should be cleared
              # Or if the tool result contains content that should be cleared
              tool_result.name in tools_to_clear or
                case tool_result.content do
                  content_parts when is_list(content_parts) ->
                    Enum.any?(content_parts, fn
                      %ContentPart{type: :image, options: options} ->
                        # Contains screenshot content that should be cleared
                        clear_screenshot_content and Keyword.get(options || [], :media) == :png

                      %ContentPart{type: :text, content: text_content} ->
                        # Contains UI content that should be cleared
                        clear_ui_content and String.starts_with?(text_content, "Current UI")

                      _ ->
                        false
                    end)

                  other when is_binary(other) ->
                    # Handle string content that might start with "Current UI"
                    clear_ui_content and String.starts_with?(other, "Current UI")

                  _ ->
                    false
                end
            end)
            |> Enum.map(fn tool_result ->
              Map.get(tool_result, :tool_call_id) || Map.get(tool_result, "tool_call_id")
            end)
            |> Enum.reject(&is_nil/1)

          _ ->
            []
        end
      end)
      |> MapSet.new()

    # Second pass: clear messages, removing tool_calls if their results will be removed
    messages
    |> Enum.map(&clear_ui_and_screenshot_content(&1, clear_ui_content, clear_screenshot_content, tool_results_to_remove))
    |> Enum.reject(&is_message_empty?/1)
  end

  defp is_message_empty?(message) do
    # A message is considered empty if it has no content, no tool calls, and no tool results
    content_empty =
      case message.content do
        nil -> true
        [] -> true
        _ -> false
      end

    tool_calls_empty =
      case message.tool_calls do
        nil -> true
        [] -> true
        _ -> false
      end

    tool_results_empty =
      case message.tool_results do
        nil -> true
        [] -> true
        _ -> false
      end

    content_empty and tool_calls_empty and tool_results_empty
  end

  defp clear_ui_and_screenshot_content(message, clear_ui_content, clear_screenshot_content, tool_results_to_remove) do
    # Clear content from message based on what should be cleared
    updated_content =
      case message.content do
        content_parts when is_list(content_parts) ->
          Enum.reject(content_parts, fn
            %ContentPart{type: :image, options: options} ->
              # Remove screenshot content (images with media: :png) if clearing screenshots
              clear_screenshot_content and Keyword.get(options || [], :media) == :png

            %ContentPart{type: :text, content: text_content} ->
              # Remove describe_ui content if clearing UI content
              clear_ui_content and String.starts_with?(text_content, "Current UI")

            _ ->
              false
          end)

        other ->
          other
      end

    # Clear tool results based on what should be cleared
    tools_to_clear = []
    tools_to_clear = if clear_ui_content, do: ["describe_ui" | tools_to_clear], else: tools_to_clear
    tools_to_clear = if clear_screenshot_content, do: ["screenshot" | tools_to_clear], else: tools_to_clear

    updated_tool_results =
      case message.tool_results do
        tool_results when is_list(tool_results) ->
          Enum.reject(tool_results, fn tool_result ->
            # Remove if tool name should be cleared
            # Or if the tool result contains content that should be cleared
            tool_result.name in tools_to_clear or
              tool_result_contains_clearable_content?(tool_result, clear_ui_content, clear_screenshot_content)
          end)

        other ->
          other
      end

    # Clear tool calls if their corresponding tool_results will be removed
    updated_tool_calls =
      case message.tool_calls do
        tool_calls when is_list(tool_calls) ->
          Enum.reject(tool_calls, fn tool_call ->
            # Remove tool_call if its result will be removed
            call_id = Map.get(tool_call, :call_id) || Map.get(tool_call, "call_id")
            call_id && MapSet.member?(tool_results_to_remove, call_id)
          end)

        other ->
          other
      end

    %{message | content: updated_content, tool_results: updated_tool_results, tool_calls: updated_tool_calls}
  end

  defp tool_result_contains_clearable_content?(tool_result, clear_ui_content, clear_screenshot_content) do
    case tool_result.content do
      content_parts when is_list(content_parts) ->
        Enum.any?(content_parts, fn
          %ContentPart{type: :image, options: options} ->
            # Contains screenshot content that should be cleared
            clear_screenshot_content and Keyword.get(options || [], :media) == :png

          %ContentPart{type: :text, content: text_content} ->
            # Contains UI content that should be cleared
            clear_ui_content and String.starts_with?(text_content, "Current UI")

          _ ->
            false
        end)

      other when is_binary(other) ->
        # Handle string content that might start with "Current UI"
        clear_ui_content and String.starts_with?(other, "Current UI")

      _ ->
        false
    end
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
