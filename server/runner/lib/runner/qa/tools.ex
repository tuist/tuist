defmodule Runner.QA.Tools do
  @moduledoc """
  QA tools such as for iOS Simulator interaction.
  """
  alias LangChain.Function
  alias LangChain.FunctionParam
  alias LangChain.Message.ContentPart
  alias LangChain.Message.ToolResult
  alias Runner.QA.Client

  require Logger

  def tools(params) do
    [
      describe_ui_tool(),
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

  defp describe_ui_tool do
    Function.new!(%{
      name: "describe_ui",
      description:
        "Retrieves the entire view hierarchy with precise frame coordinates for all visible elements. Use this tool only if you don't have a recent UI state description.",
      parameters: [
        FunctionParam.new!(%{
          name: "simulator_uuid",
          type: :string,
          description: "The UUID of the simulator",
          required: true
        })
      ],
      function: fn %{"simulator_uuid" => simulator_uuid} = _params, context ->
        case run_axe_command(simulator_uuid, ["describe-ui"]) do
          {:ok, content} ->
            simplified_content = simplify_ui_description(content)

            if should_scan_webview(content) do
              describe_webview_ui(content, simulator_uuid)
            else
              {:ok, simplified_content}
            end

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
         project_handle: project_handle
       }) do
    Function.new!(%{
      name: "tap",
      description:
        "Simulates a tap at specific x, y coordinates. Use describe_ui for precise coordinates (don't guess from screenshots). Use the exact x, y coordinates from the UI state description.",
      parameters: [
        FunctionParam.new!(%{
          name: "simulator_uuid",
          type: :string,
          description: "The UUID of the simulator",
          required: true
        }),
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
          name: "title",
          type: :string,
          description: "Brief title describing your action",
          required: true
        })
      ],
      function: fn %{
                     "simulator_uuid" => simulator_uuid,
                     "x" => x,
                     "y" => y,
                     "title" => title
                   },
                   _context ->
        action_result = run_axe_command(simulator_uuid, ["tap", "-x", "#{x}", "-y", "#{y}"])

        execute_action_with_step_report(action_result, %{
          simulator_uuid: simulator_uuid,
          title: title,
          file_name: "tap_#{x}_#{y}_#{:os.system_time(:millisecond)}",
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle
        })
      end
    })
  end

  defp long_press_tool(%{
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle
       }) do
    Function.new!(%{
      name: "long_press",
      description: "Performs a long press at coordinates with configurable duration",
      parameters: [
        FunctionParam.new!(%{
          name: "simulator_uuid",
          type: :string,
          description: "The UUID of the simulator",
          required: true
        }),
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
          name: "title",
          type: :string,
          description: "Brief title describing your action",
          required: true
        })
      ],
      function: fn %{"simulator_uuid" => simulator_uuid, "x" => x, "y" => y, "title" => title} = params, _context ->
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
          title: title,
          file_name: "long_press_#{x}_#{y}_#{:os.system_time(:millisecond)}",
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle
        })
      end
    })
  end

  defp swipe_tool(%{
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle
       }) do
    Function.new!(%{
      name: "swipe",
      description: "Executes a swipe between two coordinate points",
      parameters: [
        FunctionParam.new!(%{
          name: "simulator_uuid",
          type: :string,
          description: "The UUID of the simulator",
          required: true
        }),
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
          name: "title",
          type: :string,
          description: "Brief title describing your action",
          required: true
        })
      ],
      function: fn %{
                     "simulator_uuid" => simulator_uuid,
                     "from_x" => from_x,
                     "from_y" => from_y,
                     "to_x" => to_x,
                     "to_y" => to_y,
                     "title" => title
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

        execute_action_with_step_report(action_result, %{
          simulator_uuid: simulator_uuid,
          title: title,
          file_name: "swipe_#{from_x}_#{from_y}_to_#{to_x}_#{to_y}_#{:os.system_time(:millisecond)}",
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle
        })
      end
    })
  end

  defp type_text_tool(%{
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle
       }) do
    Function.new!(%{
      name: "type_text",
      description: "Types text using the US keyboard",
      parameters: [
        FunctionParam.new!(%{
          name: "simulator_uuid",
          type: :string,
          description: "The UUID of the simulator",
          required: true
        }),
        FunctionParam.new!(%{
          name: "text",
          type: :string,
          description: "Text to type",
          required: true
        }),
        FunctionParam.new!(%{
          name: "title",
          type: :string,
          description: "Brief title describing your action",
          required: true
        })
      ],
      function: fn %{"simulator_uuid" => simulator_uuid, "text" => text, "title" => title} = _params, _context ->
        action_result = run_axe_command(simulator_uuid, ["type", text])

        execute_action_with_step_report(action_result, %{
          simulator_uuid: simulator_uuid,
          title: title,
          file_name: "type_text_#{:os.system_time(:millisecond)}",
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle
        })
      end
    })
  end

  defp key_press_tool(%{
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle
       }) do
    Function.new!(%{
      name: "key_press",
      description: "Presses a specific key by its HID keycode",
      parameters: [
        FunctionParam.new!(%{
          name: "simulator_uuid",
          type: :string,
          description: "The UUID of the simulator",
          required: true
        }),
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
          name: "title",
          type: :string,
          description: "Brief title describing your action",
          required: true
        })
      ],
      function: fn %{"simulator_uuid" => simulator_uuid, "keycode" => keycode, "title" => title} = params, _context ->
        duration = Map.get(params, "duration", 0.1)

        action_result = run_axe_command(simulator_uuid, ["key", keycode, "--duration", "#{duration}"])

        execute_action_with_step_report(action_result, %{
          simulator_uuid: simulator_uuid,
          title: title,
          file_name: "key_press_#{keycode}_#{:os.system_time(:millisecond)}",
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle
        })
      end
    })
  end

  defp button_tool(%{
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle
       }) do
    Function.new!(%{
      name: "button",
      description: "Simulates hardware button presses (home, lock, side-button, etc.)",
      parameters: [
        FunctionParam.new!(%{
          name: "simulator_uuid",
          type: :string,
          description: "The UUID of the simulator",
          required: true
        }),
        FunctionParam.new!(%{
          name: "button",
          type: :string,
          enum: ["apple-pay", "home", "lock", "side-button", "siri"],
          description: "Press hardware button on iOS simulator.",
          required: true
        }),
        FunctionParam.new!(%{
          name: "title",
          type: :string,
          description: "Brief title describing your action",
          required: true
        })
      ],
      function: fn %{"simulator_uuid" => simulator_uuid, "button" => button_name, "title" => title} = _params, _context ->
        action_result = run_axe_command(simulator_uuid, ["button", button_name])

        execute_action_with_step_report(action_result, %{
          simulator_uuid: simulator_uuid,
          title: title,
          file_name: "button_#{button_name}_#{:os.system_time(:millisecond)}",
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle
        })
      end
    })
  end

  defp touch_tool(%{
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle
       }) do
    Function.new!(%{
      name: "touch",
      description: "Provides granular touch down/up events",
      parameters: [
        FunctionParam.new!(%{
          name: "simulator_uuid",
          type: :string,
          description: "The UUID of the simulator",
          required: true
        }),
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
          name: "title",
          type: :string,
          description: "Brief title describing your action",
          required: true
        })
      ],
      function: fn %{"simulator_uuid" => simulator_uuid, "x" => x, "y" => y, "title" => title} = params, _context ->
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
          title: title,
          file_name: "touch_#{action}_#{x}_#{y}_#{:os.system_time(:millisecond)}",
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle
        })
      end
    })
  end

  defp gesture_tool(%{
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle
       }) do
    Function.new!(%{
      name: "gesture",
      description: "Perform preset gesture patterns on the simulator",
      parameters: [
        FunctionParam.new!(%{
          name: "simulator_uuid",
          type: :string,
          description: "The UUID of the simulator",
          required: true
        }),
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
          name: "title",
          type: :string,
          description: "Brief title describing your action",
          required: true
        })
      ],
      function: fn %{"simulator_uuid" => simulator_uuid, "preset" => preset, "title" => title} = params, _context ->
        args =
          ["gesture", preset]
          |> then(&if(duration = Map.get(params, "duration"), do: &1 ++ ["--duration", "#{duration}"], else: &1))
          |> then(&if(pre_delay = Map.get(params, "pre_delay"), do: &1 ++ ["--pre-delay", "#{pre_delay}"], else: &1))
          |> then(&if(post_delay = Map.get(params, "post_delay"), do: &1 ++ ["--post-delay", "#{post_delay}"], else: &1))
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
          title: title,
          file_name: "gesture_#{preset}_#{:os.system_time(:millisecond)}",
          server_url: server_url,
          run_id: run_id,
          auth_token: auth_token,
          account_handle: account_handle,
          project_handle: project_handle
        })
      end
    })
  end

  defp screenshot_tool(%{
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle
       }) do
    Function.new!(%{
      name: "screenshot",
      description: "Captures a screenshot of the current view.",
      parameters: [
        FunctionParam.new!(%{
          name: "simulator_uuid",
          type: :string,
          description: "The UUID of the simulator",
          required: true
        })
      ],
      function: fn %{"simulator_uuid" => simulator_uuid}, _context ->
        with {:ok, temp_path} <- Briefly.create(),
             {_, 0} <- System.cmd("xcrun", ["simctl", "io", simulator_uuid, "screenshot", temp_path]),
             {:ok, image_data} <- File.read(temp_path) do
          base64_image = Base.encode64(image_data)
          {:ok, ContentPart.image!(base64_image, media: :png)}
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
         project_handle: project_handle
       }) do
    Function.new!(%{
      name: "plan_report",
      description:
        "Reports the initial QA plan as a step. Call this after creating your test plan but before executing any actions. This creates a QA step with the plan summary and captures the initial state screenshot.",
      parameters: [
        FunctionParam.new!(%{
          name: "simulator_uuid",
          type: :string,
          description: "The UUID of the simulator",
          required: true
        }),
        FunctionParam.new!(%{
          name: "plan_summary",
          type: :string,
          description: "A concise summary of the QA plan and what will be tested",
          required: true
        }),
        FunctionParam.new!(%{
          name: "plan_details",
          type: :string,
          description: "Detailed test plan including specific areas and interactions to be tested",
          required: true
        })
      ],
      function: fn %{
                     "simulator_uuid" => simulator_uuid,
                     "plan_summary" => plan_summary,
                     "plan_details" => plan_details
                   } = _params,
                   _context ->
        Logger.debug("Reporting QA plan")

        with {:ok, step_id} <-
               Client.create_step(%{
                 summary: plan_summary,
                 result: plan_details,
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
                 file_name: "qa_plan_initial_state_#{:os.system_time(:millisecond)}",
                 title: "Initial app state before QA testing",
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
             ContentPart.text!(
               "QA plan reported successfully with step_id: #{step_id}. The plan has been documented and the initial app state screenshot has been captured."
             )
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
        Logger.debug("Reporting step #{step_id}")

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
         file_name: file_name,
         title: title,
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
         {:ok, %{"url" => upload_url}} <-
           Client.screenshot_upload(%{
             file_name: file_name,
             title: title,
             server_url: server_url,
             run_id: run_id,
             auth_token: auth_token,
             account_handle: account_handle,
             project_handle: project_handle
           }),
         {:ok, _response} <- Req.put(upload_url, body: image_data, headers: [{"Content-Type", "image/png"}]),
         {:ok, _response} <-
           Client.create_screenshot(%{
             file_name: file_name,
             title: title,
             server_url: server_url,
             run_id: run_id,
             auth_token: auth_token,
             account_handle: account_handle,
             project_handle: project_handle,
             step_id: step_id
           }) do
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
      description: "Gathers the QA session summary and sends it to the server",
      parameters: [
        FunctionParam.new!(%{
          name: "summary",
          type: :string,
          description: "Summary of the QA session, including what was tested and any findings",
          required: true
        })
      ],
      function: fn %{"summary" => summary} = _params, _llm_context ->
        Logger.debug("Finalize tests: #{summary}")

        case Client.finalize_run(%{
               summary: summary,
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

  defp should_scan_webview(ui_content) do
    case JSON.decode(ui_content) do
      {:ok, ui_data} when is_list(ui_data) ->
        case ui_data do
          [%{"role" => "AXApplication", "children" => []}] -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  defp describe_webview_ui(ui_content, simulator_uuid) do
    grid_size = 50

    case screen_dimensions(ui_content) do
      {:ok, {width, height}} ->
        scan_points_with_idb(simulator_uuid, width, height, grid_size)

      {:error, reason} ->
        {:error, "Failed to get screen dimensions: #{reason}"}
    end
  end

  defp screen_dimensions(ui_content) do
    case JSON.decode(ui_content) do
      {:ok, ui_data} ->
        find_window_frame(ui_data)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_window_frame(elements) do
    Enum.find_value(elements, {:error, :window_frame_not_found}, fn element ->
      case element do
        %{"type" => type, "frame" => frame} when type in ["Window", "Application"] ->
          {:ok, {frame["width"], frame["height"]}}

        _ ->
          nil
      end
    end)
  end

  defp scan_points_with_idb(simulator_uuid, width, height, grid_size) do
    # Generate all points to scan
    points =
      for x <- 0..trunc(width)//grid_size,
          y <- 0..trunc(height)//grid_size do
        {x, y}
      end

    tasks =
      Enum.map(points, fn {x, y} ->
        Task.async(fn ->
          case run_idb_describe_point(simulator_uuid, x, y) do
            {:ok, point_info} ->
              case JSON.decode(point_info) do
                {:ok, element} -> {:ok, element}
                {:error, _} -> :error
              end

            {:error, _} ->
              :error
          end
        end)
      end)

    # Await all tasks in this chunk and collect successful results
    elements =
      tasks
      |> Task.await_many(20_000)
      |> Enum.filter(fn
        {:ok, _element} -> true
        :error -> false
      end)
      |> Enum.map(fn {:ok, element} -> element end)
      |> Enum.uniq_by(fn element -> element["AXUniqueId"] || {element["frame"], element["AXLabel"]} end)

    {:ok, "Current UI state: #{JSON.encode!(elements)}"}
  end

  defp run_idb_describe_point(simulator_uuid, x, y) do
    case System.cmd("idb", ["ui", "describe-point", "--udid", simulator_uuid, "--json", "#{x}", "#{y}"]) do
      {output, 0} ->
        {:ok, String.trim(output)}

      {error, status} ->
        {:error, "idb describe-point failed (status #{status}): #{error}"}
    end
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

  defp simplify_ui_description(describe_ui_output) when is_binary(describe_ui_output) do
    case JSON.decode(describe_ui_output) do
      {:ok, ui_data} ->
        simplified = simplify_ui_tree(ui_data)

        JSON.encode!(simplified)

      {:error, _} ->
        describe_ui_output
    end
  end

  defp simplify_ui_tree(elements) when is_list(elements) do
    Enum.map(elements, &simplify_ui_element/1)
  end

  defp simplify_ui_tree(element) when is_map(element) do
    simplify_ui_element(element)
  end

  defp simplify_ui_element(element) when is_map(element) do
    %{}
    |> then(&if type = element["type"], do: Map.put(&1, "type", type), else: &1)
    |> then(
      &if label = element["AXLabel"],
        do: Map.put(&1, "label", label),
        else: &1
    )
    |> then(fn simplified ->
      # Add role if it's different from type
      role = element["role"]
      if role && role != "AX#{element["type"]}", do: Map.put(simplified, "role", role), else: simplified
    end)
    |> then(
      &if frame = element["frame"] do
        Map.put(&1, "frame", %{
          "x" => round_if_needed(frame["x"]),
          "y" => round_if_needed(frame["y"]),
          "width" => round_if_needed(frame["width"]),
          "height" => round_if_needed(frame["height"])
        })
      else
        &1
      end
    )
    |> then(&if element["enabled"] == false, do: Map.put(&1, "enabled", false), else: &1)
    |> then(fn simplified ->
      children = element["children"]

      if children && children != [] do
        Map.put(simplified, "children", simplify_ui_tree(children))
      else
        simplified
      end
    end)
  end

  defp round_if_needed(value) when is_float(value) do
    # Round to 2 decimal places to avoid floating point precision issues
    Float.round(value, 2)
  end

  defp round_if_needed(value), do: value

  defp get_ui_description(simulator_uuid) do
    case run_axe_command(simulator_uuid, ["describe-ui"]) do
      {:ok, content} ->
        simplified_content = simplify_ui_description(content)

        if should_scan_webview(content) do
          describe_webview_ui(content, simulator_uuid)
        else
          {:ok, "Current UI state: #{simplified_content}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_action_with_step_report(action_result, %{
         simulator_uuid: simulator_uuid,
         title: title,
         file_name: file_name,
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle
       }) do
    with {:ok, _} <- action_result,
         {:ok, step_id} <-
           Client.create_step(%{
             summary: title,
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
             file_name: file_name,
             title: "After action: #{title}",
             server_url: server_url,
             run_id: run_id,
             auth_token: auth_token,
             account_handle: account_handle,
             project_handle: project_handle,
             step_id: step_id
           }),
         {:ok, ui_description} <- get_ui_description(simulator_uuid) do
      {:ok,
       [
         screenshot_content,
         ContentPart.text!("Current UI state:\n#{ui_description}"),
         ContentPart.text!(step_id)
       ]}
    end
  end
end
