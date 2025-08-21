defmodule Runner.QA.Tools do
  @moduledoc """
  QA tools such as for iOS Simulator interaction.
  """
  alias LangChain.Function
  alias LangChain.FunctionParam
  alias LangChain.Message.ContentPart
  alias Runner.QA.AppiumClient
  alias Runner.QA.Client

  require Logger

  def tools(params) do
    [
      describe_ui_tool(params),
      tap_tool(params),
      long_press_tool(params),
      swipe_tool(params),
      type_text_tool(params),
      key_press_tool(params),
      button_tool(params),
      touch_tool(params),
      gesture_tool(params),
      screenshot_tool(params),
      plan_report_tool(params),
      step_report_tool(params),
      finalize_tool(params)
    ]
  end

  defp describe_ui_tool(params) do
    Function.new!(%{
      name: "describe_ui",
      description:
        "Retrieves the entire view hierarchy with precise frame coordinates for all visible elements. Use this tool only if you don't have a recent UI state description.",
      function: fn _params, _context ->
        appium_session = Map.get(params, :appium_session)
        case AppiumClient.get_page_source(appium_session) do
          {:ok, xml_content} ->
            simplified_content = simplify_appium_ui_description(xml_content)
            {:ok, [ContentPart.text!("Current UI state: #{simplified_content}")]}

          {:error, reason} ->
            {:error, reason}
        end
      end
    })
  end

  defp tap_tool(%{
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle,
         bundle_identifier: bundle_identifier,
         simulator_uuid: simulator_uuid,
         appium_session: appium_session
       }) do
    Function.new!(%{
      name: "tap",
      description:
        "Simulates a tap at specific x, y coordinates. Use describe_ui for precise coordinates (don't guess from screenshots). Use the exact x, y coordinates from the UI state description.",
      parameters: [
        FunctionParam.new!(%{
          name: "x",
          type: :number,
          description: "X coordinate to tap",
          required: true
        }),
        FunctionParam.new!(%{
          name: "y",
          type: :number,
          description: "Y coordinate to tap",
          required: true
        }),
        FunctionParam.new!(%{
          name: "action",
          type: :string,
          description: "Brief title describing your action",
          required: true
        })
      ],
      function: fn %{
                     "x" => x,
                     "y" => y,
                     "action" => action
                   },
                   _context ->
        action_result = run_axe_command(simulator_uuid, ["tap", "-x", "#{x}", "-y", "#{y}"])

        execute_action_with_step_report(action_result, %{
          simulator_uuid: simulator_uuid,
          action: action,
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle,
          bundle_identifier: bundle_identifier,
          appium_session: appium_session
        })
      end
    })
  end

  defp long_press_tool(%{
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle,
         bundle_identifier: bundle_identifier,
         simulator_uuid: simulator_uuid,
         appium_session: appium_session
       }) do
    Function.new!(%{
      name: "long_press",
      description: "Performs a long press at coordinates with configurable duration",
      parameters: [
        FunctionParam.new!(%{
          name: "x",
          type: :number,
          description: "X coordinate to long press",
          required: true
        }),
        FunctionParam.new!(%{
          name: "y",
          type: :number,
          description: "Y coordinate to long press",
          required: true
        }),
        FunctionParam.new!(%{
          name: "duration",
          type: :number,
          description: "Duration in seconds",
          required: false,
          default: 1.0
        }),
        FunctionParam.new!(%{
          name: "action",
          type: :string,
          description: "Brief title describing your action",
          required: true
        })
      ],
      function: fn %{"x" => x, "y" => y, "action" => action} =
                     params,
                   _context ->
        duration = Map.get(params, "duration", 1.0)

        action_result =
          run_axe_command(simulator_uuid, [
            "touch",
            "-x",
            "#{x}",
            "-y",
            "#{y}",
            "--down",
            "--up",
            "--delay",
            "#{duration}"
          ])

        execute_action_with_step_report(action_result, %{
          simulator_uuid: simulator_uuid,
          action: action,
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle,
          bundle_identifier: bundle_identifier,
          appium_session: appium_session
        })
      end
    })
  end

  defp swipe_tool(%{
         server_url: _server_url,
         run_id: _run_id,
         auth_token: _auth_token,
         account_handle: _account_handle,
         project_handle: _project_handle,
         bundle_identifier: _bundle_identifier,
         simulator_uuid: simulator_uuid,
         appium_session: _appium_session
       } = all_params) do
    Function.new!(%{
      name: "swipe",
      description: "Executes a swipe between two coordinate points",
      parameters: [
        FunctionParam.new!(%{
          name: "from_x",
          type: :number,
          description: "Starting X coordinate",
          required: true
        }),
        FunctionParam.new!(%{
          name: "from_y",
          type: :number,
          description: "Starting Y coordinate",
          required: true
        }),
        FunctionParam.new!(%{
          name: "to_x",
          type: :number,
          description: "Ending X coordinate",
          required: true
        }),
        FunctionParam.new!(%{
          name: "to_y",
          type: :number,
          description: "Ending Y coordinate",
          required: true
        }),
        FunctionParam.new!(%{
          name: "duration",
          type: :number,
          description: "Duration in seconds",
          required: false,
          default: 0.5
        }),
        FunctionParam.new!(%{
          name: "action",
          type: :string,
          description: "Brief title describing your action",
          required: true
        })
      ],
      function: fn %{
                     "from_x" => from_x,
                     "from_y" => from_y,
                     "to_x" => to_x,
                     "to_y" => to_y,
                     "action" => action
                   } = params,
                   _context ->
        duration = Map.get(params, "duration", 0.5)

        action_result =
          run_axe_command(simulator_uuid, [
            "swipe",
            "--start-x",
            "#{from_x}",
            "--start-y",
            "#{from_y}",
            "--end-x",
            "#{to_x}",
            "--end-y",
            "#{to_y}",
            "--duration",
            "#{duration}"
          ])

        execute_action_with_step_report(action_result, all_params |> Map.put(:action, action))
      end
    })
  end

  defp type_text_tool(%{
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle,
         bundle_identifier: bundle_identifier,
         simulator_uuid: simulator_uuid,
         appium_session: appium_session
       }) do
    Function.new!(%{
      name: "type_text",
      description: "Types text using the US keyboard",
      parameters: [
        FunctionParam.new!(%{
          name: "text",
          type: :string,
          description: "Text to type",
          required: true
        }),
        FunctionParam.new!(%{
          name: "action",
          type: :string,
          description: "Brief title describing your action",
          required: true
        })
      ],
      function: fn %{"text" => text, "action" => action} =
                     _params,
                   _context ->
        action_result = run_axe_command(simulator_uuid, ["type", text])

        execute_action_with_step_report(action_result, %{
          simulator_uuid: simulator_uuid,
          action: action,
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle,
          bundle_identifier: bundle_identifier,
          appium_session: appium_session
        })
      end
    })
  end

  defp key_press_tool(%{
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle,
         bundle_identifier: bundle_identifier,
         simulator_uuid: simulator_uuid,
         appium_session: appium_session
       }) do
    Function.new!(%{
      name: "key_press",
      description: "Presses a specific key by its HID keycode",
      parameters: [
        FunctionParam.new!(%{
          name: "keycode",
          type: :string,
          description: """
          Press individual keys using their HID keycode values.

          Common keycodes:
            40 - Return/Enter
            42 - Backspace
            43 - Tab
            44 - Space
            58-67 - F1-F10
            224-231 - Modifier keys (Ctrl, Shift, Alt, etc.)
          """,
          required: true
        }),
        FunctionParam.new!(%{
          name: "duration",
          type: :number,
          description: "Duration to hold the key in seconds",
          required: false,
          default: 0.1
        }),
        FunctionParam.new!(%{
          name: "action",
          type: :string,
          description: "Brief title describing your action",
          required: true
        })
      ],
      function: fn %{"keycode" => keycode, "action" => action} =
                     params,
                   _context ->
        duration = Map.get(params, "duration", 0.1)

        action_result =
          run_axe_command(simulator_uuid, ["key", keycode, "--duration", "#{duration}"])

        execute_action_with_step_report(action_result, %{
          simulator_uuid: simulator_uuid,
          action: action,
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle,
          bundle_identifier: bundle_identifier,
          appium_session: appium_session
        })
      end
    })
  end

  defp button_tool(%{
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle,
         bundle_identifier: bundle_identifier,
         simulator_uuid: simulator_uuid,
         appium_session: appium_session
       }) do
    Function.new!(%{
      name: "button",
      description: "Simulates hardware button presses (home, lock, side-button, etc.)",
      parameters: [
        FunctionParam.new!(%{
          name: "button",
          type: :string,
          enum: ["apple-pay", "home", "lock", "side-button", "siri"],
          description: "Press hardware button on iOS simulator.",
          required: true
        }),
        FunctionParam.new!(%{
          name: "action",
          type: :string,
          description: "Brief title describing your action",
          required: true
        })
      ],
      function: fn %{
                     "button" => button_name,
                     "action" => action
                   } = _params,
                   _context ->
        action_result = run_axe_command(simulator_uuid, ["button", button_name])

        execute_action_with_step_report(action_result, %{
          simulator_uuid: simulator_uuid,
          action: action,
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle,
          bundle_identifier: bundle_identifier,
          appium_session: appium_session
        })
      end
    })
  end

  defp touch_tool(%{
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle,
         bundle_identifier: bundle_identifier,
         simulator_uuid: simulator_uuid,
         appium_session: appium_session
       }) do
    Function.new!(%{
      name: "touch",
      description: "Provides granular touch down/up events",
      parameters: [
        FunctionParam.new!(%{
          name: "x",
          type: :number,
          description: "X coordinate",
          required: true
        }),
        FunctionParam.new!(%{
          name: "y",
          type: :number,
          description: "Y coordinate",
          required: true
        }),
        FunctionParam.new!(%{
          name: "action",
          type: :string,
          enum: ["down", "up", "down-up"],
          description:
            "Perform touch down/up events at specific coordinates. Use describe_ui for precise coordinates (don't guess from screenshots).",
          required: false,
          default: "tap"
        }),
        FunctionParam.new!(%{
          name: "action",
          type: :string,
          description: "Brief title describing your action",
          required: true
        })
      ],
      function: fn %{"x" => x, "y" => y, "action" => _action} =
                     params,
                   _context ->
        action = Map.get(params, "action", "down-up")
        args = ["touch", "#{x}", "#{y}"]

        args =
          case action do
            "down" -> args ++ ["--down"]
            "up" -> args ++ ["--up"]
            "down-up" -> args ++ ["--down", "--up"]
          end

        action_result = run_axe_command(simulator_uuid, args)

        execute_action_with_step_report(action_result, %{
          simulator_uuid: simulator_uuid,
          action: action,
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle,
          bundle_identifier: bundle_identifier,
          appium_session: appium_session
        })
      end
    })
  end

  defp gesture_tool(%{
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle,
         bundle_identifier: bundle_identifier,
         simulator_uuid: simulator_uuid,
         appium_session: appium_session
       }) do
    Function.new!(%{
      name: "gesture",
      description: "Perform preset gesture patterns on the simulator",
      parameters: [
        FunctionParam.new!(%{
          name: "preset",
          type: :string,
          enum: [
            "scroll-up",
            "scroll-down",
            "scroll-left",
            "scroll-right",
            "swipe-from-left-edge",
            "swipe-from-right-edge",
            "swipe-from-top-edge",
            "swipe-from-bottom-edge"
          ],
          description: "Preset gesture pattern to perform",
          required: true
        }),
        FunctionParam.new!(%{
          name: "screen_width",
          type: :number,
          description: "Screen width in pixels (for calculating gesture coordinates)",
          required: false
        }),
        FunctionParam.new!(%{
          name: "screen_height",
          type: :number,
          description: "Screen height in pixels (for calculating gesture coordinates)",
          required: false
        }),
        FunctionParam.new!(%{
          name: "duration",
          type: :number,
          description: "Gesture duration in seconds",
          required: false
        }),
        FunctionParam.new!(%{
          name: "delta",
          type: :number,
          description: "Distance to move in pixels",
          required: false
        }),
        FunctionParam.new!(%{
          name: "pre_delay",
          type: :number,
          description: "Delay before starting gesture in seconds",
          required: false
        }),
        FunctionParam.new!(%{
          name: "post_delay",
          type: :number,
          description: "Delay after completing gesture in seconds",
          required: false
        }),
        FunctionParam.new!(%{
          name: "action",
          type: :string,
          description: "Brief title describing your action",
          required: true
        })
      ],
      function: fn %{"preset" => preset, "action" => action} =
                     params,
                   _context ->
        args =
          ["gesture", preset]
          |> then(
            &if(duration = Map.get(params, "duration"),
              do: &1 ++ ["--duration", "#{duration}"],
              else: &1
            )
          )
          |> then(
            &if(pre_delay = Map.get(params, "pre_delay"),
              do: &1 ++ ["--pre-delay", "#{pre_delay}"],
              else: &1
            )
          )
          |> then(
            &if(post_delay = Map.get(params, "post_delay"),
              do: &1 ++ ["--post-delay", "#{post_delay}"],
              else: &1
            )
          )
          |> then(&if(delta = Map.get(params, "delta"), do: &1 ++ ["--delta", "#{delta}"], else: &1))
          |> then(
            &if(screen_height = Map.get(params, "screen_height"),
              do: &1 ++ ["--screen-height", "#{screen_height}"],
              else: &1
            )
          )
          |> then(
            &if(screen_width = Map.get(params, "screen_width"),
              do: &1 ++ ["--screen-width", "#{screen_width}"],
              else: &1
            )
          )

        action_result = run_axe_command(simulator_uuid, args)

        execute_action_with_step_report(action_result, %{
          simulator_uuid: simulator_uuid,
          action: action,
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle,
          bundle_identifier: bundle_identifier,
          appium_session: appium_session
        })
      end
    })
  end

  defp screenshot_tool(%{simulator_uuid: simulator_uuid}) do
    Function.new!(%{
      name: "screenshot",
      description: "Captures a screenshot of the current view.",
      parameters: [],
      function: fn _params, _context ->
        with {:ok, temp_path} <- Briefly.create(),
             {_, 0} <-
               System.cmd("xcrun", ["simctl", "io", simulator_uuid, "screenshot", temp_path]),
             {:ok, image_data} <- File.read(temp_path) do
          base64_image = Base.encode64(image_data)
          {:ok, [ContentPart.image!(base64_image, media: :png)]}
        else
          {:error, reason} -> {:error, "Failed to capture screenshot: #{reason}"}
          {reason, _status} -> {:error, "Failed to capture screenshot: #{reason}"}
        end
      end
    })
  end

  defp plan_report_tool(%{
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle,
         simulator_uuid: simulator_uuid
       }) do
    Function.new!(%{
      name: "plan_report",
      description:
        "Reports the initial QA plan. Call this after creating your test plan but before executing any actions.",
      parameters: [
        FunctionParam.new!(%{
          name: "summary",
          type: :string,
          description: "A concise summary of the QA plan and what will be tested",
          required: true
        }),
        FunctionParam.new!(%{
          name: "details",
          type: :string,
          description: "Detailed test plan including specific areas and interactions to be tested",
          required: true
        })
      ],
      function: fn %{
                     "summary" => summary,
                     "details" => details
                   },
                   _context ->
        with {:ok, step_id} <-
               Client.create_step(%{
                 action: summary,
                 result: details,
                 issues: [],
                 server_url: server_url,
                 run_id: run_id,
                 auth_token: auth_token,
                 account_handle: account_handle,
                 project_handle: project_handle
               }),
             {:ok, screenshot_content} <-
               capture_and_upload_screenshot(%{
                 simulator_uuid: simulator_uuid,
                 server_url: server_url,
                 run_id: run_id,
                 auth_token: auth_token,
                 account_handle: account_handle,
                 project_handle: project_handle,
                 step_id: step_id
               }) do
          {:ok,
           [
             screenshot_content,
             ContentPart.text!("The QA plan has been documented and the initial app state screenshot has been captured.")
           ]}
        else
          {:error, reason} -> {:error, "Failed to report QA plan: #{reason}"}
        end
      end
    })
  end

  defp step_report_tool(%{
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle
       }) do
    Function.new!(%{
      name: "step_report",
      description: """
      Reports the result and any issues found after each interaction with the app. Use this to document whether the action achieved its expected outcome and to report any visual or functional issues.

      Follow these guidelines when reporting visual incosistencies or functional issues:
      - Don't report pre-filled fields as issues
      - Don't read labels from the screenshot. Always read them from the UI state.
      """,
      parameters: [
        FunctionParam.new!(%{
          name: "step_id",
          type: :string,
          description: "The ID of the step to report on (returned from actions like tap)",
          required: true
        }),
        FunctionParam.new!(%{
          name: "result",
          type: :string,
          description: "Detailed description of what happened - did the action achieve its expected outcome?",
          required: true
        }),
        FunctionParam.new!(%{
          name: "issues",
          type: :array,
          item_type: "string",
          description:
            "List of any issues found (e.g., visual glitches, unexpected behavior, accessibility problems). Don't create separate entries for related issues.",
          required: true
        })
      ],
      function: fn %{"step_id" => step_id, "result" => result, "issues" => issues} = _params, _context ->
        case Client.update_step(%{
               step_id: step_id,
               result: result,
               issues: issues,
               server_url: server_url,
               run_id: run_id,
               auth_token: auth_token,
               account_handle: account_handle,
               project_handle: project_handle
             }) do
          {:ok, _} ->
            {:ok, "Step report submitted successfully."}

          {:error, reason} ->
            {:error, "Failed to submit step report: #{reason}"}
        end
      end
    })
  end

  defp capture_and_upload_screenshot(%{
         simulator_uuid: simulator_uuid,
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle,
         step_id: step_id
       }) do
    with {:ok, temp_path} <- Briefly.create(),
         {_, 0} <- System.cmd("xcrun", ["simctl", "io", simulator_uuid, "screenshot", temp_path]),
         {:ok, image_data} <- File.read(temp_path),
         {:ok, %{"id" => screenshot_id}} <-
           Client.create_screenshot(%{
             server_url: server_url,
             run_id: run_id,
             auth_token: auth_token,
             account_handle: account_handle,
             project_handle: project_handle,
             step_id: step_id
           }),
         {:ok, %{"url" => upload_url}} <-
           Client.screenshot_upload(%{
             server_url: server_url,
             run_id: run_id,
             auth_token: auth_token,
             account_handle: account_handle,
             project_handle: project_handle,
             screenshot_id: screenshot_id
           }),
         {:ok, _response} <-
           Req.put(upload_url, body: image_data, headers: [{"Content-Type", "image/png"}]) do
      base64_image = Base.encode64(image_data)
      {:ok, ContentPart.image!(base64_image, media: :png)}
    else
      {:error, reason} -> {:error, "Failed to capture screenshot: #{reason}"}
      {reason, _status} -> {:error, "Failed to capture screenshot: #{reason}"}
    end
  end

  defp finalize_tool(%{
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle
       }) do
    Function.new!(%{
      name: "finalize",
      description: "Marks the QA session as completed",
      parameters: [],
      function: fn _params, _llm_context ->
        case Client.finalize_run(%{
               server_url: server_url,
               run_id: run_id,
               auth_token: auth_token,
               account_handle: account_handle,
               project_handle: project_handle
             }) do
          {:ok, _} -> {:ok, "QA test run finished successfully and status updated."}
          {:error, reason} -> {:error, "Failed to update run status: #{reason}"}
        end
      end
    })
  end

  defp run_axe_command(simulator_uuid, args) do
    full_params = args ++ ["--udid", simulator_uuid]

    case System.cmd("/opt/homebrew/bin/axe", full_params) do
      {output, 0} ->
        {:ok, String.trim(output)}

      {error, status} ->
        {:error, "axe command failed (status #{status}): #{error}"}
    end
  end

  defp round_if_needed(value) when is_float(value) do
    # Round to 2 decimal places to avoid floating point precision issues
    Float.round(value, 2)
  end

  defp round_if_needed(value), do: value

  defp ui_description_from_appium_session(appium_session) do
    case AppiumClient.get_page_source(appium_session) do
      {:ok, xml_content} ->
        simplified_content = simplify_appium_ui_description(xml_content)
        {:ok, "Current UI state: #{simplified_content}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_action_with_step_report(action_result, %{
         simulator_uuid: simulator_uuid,
         action: action,
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle,
         bundle_identifier: _bundle_identifier,
         appium_session: appium_session
       }) do
    with {:ok, _} <- action_result,
         {:ok, step_id} <-
           Client.create_step(%{
             action: action,
             issues: [],
             server_url: server_url,
             run_id: run_id,
             auth_token: auth_token,
             account_handle: account_handle,
             project_handle: project_handle
           }),
         {:ok, screenshot_content} <-
           capture_and_upload_screenshot(%{
             simulator_uuid: simulator_uuid,
             server_url: server_url,
             run_id: run_id,
             auth_token: auth_token,
             account_handle: account_handle,
             project_handle: project_handle,
             step_id: step_id
           }),
         {:ok, ui_description} <- ui_description_from_appium_session(appium_session) do
      {:ok,
       [
         screenshot_content,
         ContentPart.text!(ui_description),
         ContentPart.text!(step_id)
       ]}
    end
  end

  defp simplify_appium_ui_description(xml_content) do
    case parse_appium_xml(xml_content) do
      {:ok, elements} ->
        JSON.encode!(elements)

      {:error, _} ->
        # Fallback to raw content if parsing fails
        xml_content
    end
  end

  defp parse_appium_xml(xml_content) do
    case SAXMap.from_string(xml_content, ignore_attribute: false) do
      {:ok, parsed} ->
        elements = extract_elements_from_parsed_xml(parsed)
        {:ok, elements}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  defp extract_elements_from_parsed_xml(parsed) do
    # Traverse the parsed XML tree and extract UI elements
    parsed
    |> extract_elements_from_map([])
    |> List.flatten()
  end

  defp extract_elements_from_map(parsed, acc) when is_map(parsed) do
    Enum.reduce(parsed, acc, fn {key, value}, acc ->
      if String.starts_with?(key, "XCUIElementType") do
        # This is a UI element - handle both single element and lists
        elements = extract_ui_elements(key, value)
        # Continue processing nested elements
        child_elements = extract_elements_from_value(value, [])

        elements ++ child_elements ++ acc
      else
        # Not a UI element, but may contain UI elements
        extract_elements_from_value(value, acc)
      end
    end)
  end

  defp extract_elements_from_map(_, acc), do: acc

  defp extract_elements_from_value(value, acc) when is_map(value) do
    # Check if this has a "content" key (SAXMap structure when attributes are preserved)
    case Map.get(value, "content") do
      nil -> extract_elements_from_map(value, acc)
      content -> extract_elements_from_value(content, acc)
    end
  end

  defp extract_elements_from_value(value, acc) when is_list(value) do
    Enum.reduce(value, acc, fn item, acc ->
      extract_elements_from_value(item, acc)
    end)
  end

  defp extract_elements_from_value(_, acc), do: acc

  # Handle both single elements and lists of elements with same tag
  defp extract_ui_elements(tag, elements) when is_list(elements) do
    Enum.map(elements, &extract_ui_element(tag, &1))
  end

  defp extract_ui_elements(tag, element) do
    [extract_ui_element(tag, element)]
  end

  defp extract_ui_element(tag, attrs) when is_map(attrs) do
    # When ignore_attribute: false, attributes are at the same level as "content"
    name = attrs["name"]
    label = attrs["label"]
    x = attrs["x"]
    y = attrs["y"]
    width = attrs["width"]
    height = attrs["height"]
    enabled = attrs["enabled"]
    visible = attrs["visible"]

    %{
      "type" => tag,
      "label" => name || label,
      "frame" => %{
        "x" => parse_number(x),
        "y" => parse_number(y),
        "width" => parse_number(width),
        "height" => parse_number(height)
      },
      "enabled" => enabled == "true",
      "visible" => visible == "true"
    }
    |> Enum.filter(fn {_, v} -> v != nil end)
    |> Map.new()
  end

  defp extract_ui_element(tag, _), do: %{"type" => tag}

  defp parse_number(nil), do: nil

  defp parse_number(str) do
    case Float.parse(str) do
      {num, _} -> round_if_needed(num)
      :error -> nil
    end
  end
end
