defmodule Runner.QA.Agent do
  @moduledoc """
  Tuist QA agent module.
  """

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Message
  alias LangChain.Message.ContentPart
  alias LangChain.TokenUsage
  alias Runner.QA.AppiumClient
  alias Runner.QA.Client
  alias Runner.QA.Simulators
  alias Runner.QA.Sleeper
  alias Runner.QA.Tools
  alias Runner.Zip

  require Logger

  @claude_model "claude-sonnet-4-20250514"
  @openai_model "gpt-5"
  @action_tool_names [
    "tap",
    "swipe",
    "long_press",
    "type_text",
    "key_press",
    "button",
    "touch",
    "gesture"
  ]

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
        } = attrs,
        opts
      ) do
    anthropic_api_key = Keyword.get(opts, :anthropic_api_key)
    openai_api_key = Keyword.get(opts, :openai_api_key)
    launch_arguments = Map.get(attrs, :launch_arguments, "")
    app_description = Map.get(attrs, :app_description, "")
    email = Map.get(attrs, :email, "")
    password = Map.get(attrs, :password, "")

    with {:ok, simulator_device} <- simulator_device(),
         :ok <- run_preview(preview_url, bundle_identifier, simulator_device, launch_arguments),
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
           }),
         {:ok, appium_session} <-
           AppiumClient.start_session(simulator_device.udid, bundle_identifier) do
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

      app_context =
        if app_description == "",
          do: "",
          else: """

          Here's additional context about the app you're testing:
          #{app_description}
          """

      credentials_context =
        if email == "" or password == "",
          do: "",
          else: """

          Test account credentials for sign-in:
          Email: #{email}
          Password: #{password}
          Use these credentials if the app requires authentication or login.
          """

      prompt = """
      You are a QA agent testing a mobile iOS app. Test the following: #{prompt}.

      First, understand what you need to test. Then, set up a plan to test the feature and execute on it without asking for additional instructions.

      When interacting with the app, you must follow these guidelines:
      - Prefer using describe_ui over screenshot to interact with the app
      - Don't read labels from screenshots. Always read them from the UI description.
      - To dismiss a system sheet, tap within the visible screen area but outside the sheet, such in the dark/grayed area above the sheet
      - If a button includes text, prefer tapping on the text to interact with the button
      - When you recognize placeholder/pre-filled fields, you must never clear the placeholder value. Instead, replace the text directly with type_text tool.
      #{app_context}#{credentials_context}
      """

      llm =
        ChatAnthropic.new!(%{
          model: @claude_model,
          max_tokens: 2000,
          api_key: anthropic_api_key
        })

      with_fallbacks =
        if openai_api_key do
          [
            ChatOpenAI.new!(%{
              model: @openai_model,
              max_completion_tokens: 2000,
              api_key: openai_api_key
            })
          ]
        else
          []
        end

      tools =
        Tools.tools(%{
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle,
          bundle_identifier: bundle_identifier,
          appium_session: appium_session,
          simulator_uuid: simulator_device.udid
        })

      {:ok, recording_path} = Briefly.create()

      case run_llm(
             %{
               llm: llm,
               with_fallbacks: with_fallbacks,
               max_retry_count: 10,
               recording_path: recording_path,
               simulator_device: simulator_device,
               server_url: server_url,
               run_id: run_id,
               auth_token: auth_token,
               account_handle: account_handle,
               project_handle: project_handle
             },
             handler,
             [Message.new_user!(prompt)],
             tools
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

          AppiumClient.stop_session(appium_session)

          {:error, error_message}

        {:ok, attrs} ->
          upload_recording(attrs)
          AppiumClient.stop_session(appium_session)
          :ok
      end
    end
  end

  defp upload_recording(attrs) do
    :ok = Simulators.stop_recording(attrs.recording_port)
    # When we stop the recording, the file is not immediately available for reading
    Sleeper.sleep(100)

    # Only upload recording if there was at least one action performed
    if Map.has_key?(attrs, :last_action_timestamp) do
      duration_ms = DateTime.diff(attrs.last_action_timestamp, attrs.recording_started_at, :millisecond)

      {:ok, trimmed_path} = Briefly.create(extname: ".mp4")
      duration_seconds = duration_ms / 1000.0

      {recording_duration_output, 0} =
        System.cmd("ffprobe", [
          "-v",
          "quiet",
          "-print_format",
          "json",
          "-show_format",
          attrs.recording_path
        ])

      {:ok, recording_info} = JSON.decode(recording_duration_output)
      recording_duration = recording_info["format"]["duration"]
      duration_seconds = min(duration_seconds, recording_duration)

      {_, 0} =
        System.cmd("ffmpeg", [
          "-i",
          attrs.recording_path,
          "-t",
          Float.to_string(duration_seconds),
          "-c",
          "copy",
          "-y",
          trimmed_path
        ])

      {:ok, _} =
        Client.upload_recording(%{
          server_url: attrs.server_url,
          run_id: attrs.run_id,
          auth_token: attrs.auth_token,
          account_handle: attrs.account_handle,
          project_handle: attrs.project_handle,
          recording_path: trimmed_path,
          started_at: attrs.recording_started_at,
          duration_ms: duration_ms
        })
    end
  end

  defp run_llm(%{with_fallbacks: with_fallbacks} = attrs, handler, messages, tools) do
    tools_without_step_report = Enum.filter(tools, &(&1.name != "step_report"))

    attrs
    |> LLMChain.new!()
    |> LLMChain.add_messages(messages)
    |> LLMChain.add_tools(tools_without_step_report)
    |> LLMChain.add_callback(handler)
    |> LLMChain.run_until_tool_used(Enum.map(tools_without_step_report, & &1.name),
      with_fallbacks: with_fallbacks
    )
    |> process_llm_result(attrs, handler, tools)
  end

  defp process_llm_result(
         {:ok, %LLMChain{last_message: last_message, messages: messages} = _chain, tool_result},
         attrs,
         handler,
         tools
       ) do
    case tool_result.name do
      "finalize" ->
        {:ok, attrs}

      "plan_report" ->
        attrs = Map.put(attrs, :recording_started_at, DateTime.utc_now())

        recording_port =
          Simulators.start_recording(attrs.simulator_device, attrs.recording_path)

        attrs = Map.put(attrs, :recording_port, recording_port)

        messages =
          clear_ui_and_screenshot_messages(Enum.drop(messages, -1)) ++ [List.last(messages)]

        run_llm(attrs, handler, messages, tools)

      tool_name ->
        attrs =
          if tool_name in @action_tool_names do
            Map.put(attrs, :last_action_timestamp, DateTime.utc_now())
          else
            attrs
          end

        messages =
          clear_ui_and_screenshot_messages(Enum.drop(messages, -1)) ++ [List.last(messages)]

        messages =
          if tool_name in @action_tool_names and
               last_message != nil and
               last_message.tool_results != nil do
            reporting_step_for_last_action_tool(messages, attrs, handler, tools)
          else
            messages
          end

        run_llm(attrs, handler, messages, tools)
    end
  end

  defp process_llm_result({:error, _chain, %LangChain.LangChainError{message: message}}, _attrs, _handler, _tools) do
    {:error, "LLM chain execution failed: #{message}"}
  end

  defp reporting_step_for_last_action_tool(messages, attrs, handler, tools) do
    {messages, step_id} = messages_with_step_id(messages)

    report_step(attrs, handler, tools, messages, step_id)

    messages
  end

  # Extracts step_id from the last message and removes the step_id from the last message
  defp messages_with_step_id(messages) do
    last_message = List.last(messages)
    last_tool_result = List.last(last_message.tool_results)
    %{content: content_parts} = last_tool_result
    %ContentPart{type: :text, content: step_id} = List.last(content_parts)

    last_tool_result = %{
      last_tool_result
      | content: Enum.drop(content_parts, -1)
    }

    last_message = %{
      last_message
      | tool_results: Enum.drop(last_message.tool_results, -1) ++ [last_tool_result]
    }

    {Enum.drop(messages, -1) ++ [last_message], step_id}
  end

  defp report_step(attrs, handler, tools, messages, step_id) do
    attrs
    |> LLMChain.new!()
    |> LLMChain.add_messages(
      messages ++
        [
          Message.new_user!(
            "Use the returned image to analyze visual inconsistencies and report the result for step_id #{step_id} with the step_report tool."
          )
        ]
    )
    |> LLMChain.add_tools(tools)
    |> LLMChain.add_callback(handler)
    |> LLMChain.run(mode: :until_success)
  end

  defp clear_ui_and_screenshot_messages(messages) do
    messages = Enum.map(messages, &clear_ui_and_screenshot_content/1)

    tool_call_ids_with_no_content =
      messages
      |> Enum.reject(&is_nil(&1.tool_results))
      |> Enum.flat_map(& &1.tool_results)
      |> Enum.filter(&Enum.empty?(&1.content))
      |> MapSet.new(& &1.tool_call_id)

    messages =
      Enum.map(messages, fn message ->
        tool_results =
          Enum.filter(
            message.tool_results || [],
            &(&1.tool_call_id not in tool_call_ids_with_no_content)
          )

        tool_calls =
          Enum.filter(
            message.tool_calls || [],
            &(&1.call_id not in tool_call_ids_with_no_content)
          )

        %{
          message
          | tool_results: tool_results,
            tool_calls: tool_calls
        }
      end)

    Enum.reject(messages, &is_message_empty?/1)
  end

  defp is_message_empty?(message) do
    Enum.empty?(message.content || []) && Enum.empty?(message.tool_calls || []) &&
      Enum.empty?(message.tool_results || [])
  end

  defp clear_ui_and_screenshot_content(message) do
    tool_results =
      Enum.map(message.tool_results || [], fn tool_result ->
        content =
          case tool_result.content do
            content_parts when is_list(content_parts) ->
              Enum.reject(content_parts, fn
                %ContentPart{type: :image} ->
                  true

                %ContentPart{type: :text, content: text_content} ->
                  String.starts_with?(text_content, "{\"AppiumAUT\"")

                _ ->
                  false
              end)

            other ->
              other
          end

        %{tool_result | content: content}
      end)

    %{
      message
      | tool_results: tool_results
    }
  end

  defp run_preview(preview_url, bundle_identifier, simulator_device, launch_arguments) do
    with {:ok, preview_path} <- download_preview(preview_url),
         {:ok, app_path} <- extract_app_from_preview(preview_path, bundle_identifier),
         :ok <- Simulators.boot_simulator(simulator_device),
         :ok <- Simulators.install_app(app_path, simulator_device) do
      Simulators.launch_app(bundle_identifier, simulator_device, launch_arguments)
    end
  end

  defp simulator_device do
    case Simulators.devices() do
      {:ok, devices} ->
        device =
          Enum.find(devices, fn device ->
            device.name == "iPhone 17" and
              device.runtime_identifier == "com.apple.CoreSimulator.SimRuntime.iOS-26-0"
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
