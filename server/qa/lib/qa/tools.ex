defmodule QA.Tools do
  @moduledoc """
  QA tools such as for iOS Simulator interaction.
  """
  alias LangChain.Function
  alias LangChain.FunctionParam
  alias LangChain.Message.ContentPart
  alias QA.Client

  require Logger

  def tools(params) do
    [
      describe_ui_tool(),
      tap_tool(),
      long_press_tool(),
      swipe_tool(),
      type_text_tool(),
      key_press_tool(),
      button_tool(),
      touch_tool(),
      gesture_tool(),
      screenshot_tool(params),
      step_finished_tool(params),
      finalize_tool(params)
    ]
  end

  defp describe_ui_tool do
    Function.new!(%{
      name: "describe_ui",
      description: "Retrieves the entire view hierarchy with precise frame coordinates for all visible elements.",
      parameters: [
        FunctionParam.new!(%{
          name: "simulator_uuid",
          type: :string,
          description: "The UUID of the simulator",
          required: true
        })
      ],
      function: fn %{"simulator_uuid" => simulator_uuid} = _params, _context ->
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

  defp tap_tool do
    Function.new!(%{
      name: "tap",
      description:
        "Simulates a tap at specific x, y coordinates. Use describe_ui for precise coordinates (don't guess from screenshots).",
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
        })
      ],
      function: fn %{"simulator_uuid" => simulator_uuid, "x" => x, "y" => y}, _context ->
        run_axe_command(simulator_uuid, ["tap", "-x", "#{x}", "-y", "#{y}"])
      end
    })
  end

  defp long_press_tool do
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
        })
      ],
      function: fn %{"simulator_uuid" => simulator_uuid, "x" => x, "y" => y} = params, _context ->
        duration = Map.get(params, "duration", 1.0)

        case run_axe_command(simulator_uuid, [
               "touch",
               "-x",
               "#{x}",
               "-y",
               "#{y}",
               "--down",
               "--up",
               "--delay",
               "#{duration}"
             ]) do
          {:ok, _} -> {:ok, "Long press successful"}
          {:error, reason} -> {:error, reason}
        end
      end
    })
  end

  defp swipe_tool do
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
        })
      ],
      function: fn %{
                     "simulator_uuid" => simulator_uuid,
                     "from_x" => from_x,
                     "from_y" => from_y,
                     "to_x" => to_x,
                     "to_y" => to_y
                   } = params,
                   _context ->
        duration = Map.get(params, "duration", 0.5)

        case run_axe_command(simulator_uuid, [
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
             ]) do
          {:ok, _} -> {:ok, "Swipe was successful"}
          {:error, reason} -> {:error, reason}
        end
      end
    })
  end

  defp type_text_tool do
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
        })
      ],
      function: fn %{"simulator_uuid" => simulator_uuid, "text" => text} = _params, _context ->
        case run_axe_command(simulator_uuid, ["type", text]) do
          {:ok, _} -> {:ok, "Text typed successfully"}
          {:error, reason} -> {:error, reason}
        end
      end
    })
  end

  defp key_press_tool do
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
        })
      ],
      function: fn %{"simulator_uuid" => simulator_uuid, "keycode" => keycode} = params, _context ->
        duration = Map.get(params, "duration", 0.1)

        case run_axe_command(simulator_uuid, ["key", keycode, "--duration", "#{duration}"]) do
          {:ok, _} -> {:ok, "Key pressed successfully"}
          {:error, reason} -> {:error, reason}
        end
      end
    })
  end

  defp button_tool do
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
        })
      ],
      function: fn %{"simulator_uuid" => simulator_uuid, "button" => button_name} = _params, _context ->
        run_axe_command(simulator_uuid, ["button", button_name])
      end
    })
  end

  defp touch_tool do
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
        })
      ],
      function: fn %{"simulator_uuid" => simulator_uuid, "x" => x, "y" => y, "action" => action} = _params, _context ->
        args = ["touch", "#{x}", "#{y}"]

        args =
          case action do
            "down" -> args ++ ["--down"]
            "up" -> args ++ ["--up"]
            "down-up" -> args ++ ["--down", "--up"]
          end

        case run_axe_command(simulator_uuid, args) do
          {:ok, _} -> {:ok, "Touch was successful"}
          {:error, reason} -> {:error, reason}
        end
      end
    })
  end

  defp gesture_tool do
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
        })
      ],
      function: fn %{"simulator_uuid" => simulator_uuid, "preset" => preset} = params, _context ->
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

        case run_axe_command(simulator_uuid, args) do
          {:ok, _} -> {:ok, "Gesture was successful"}
          {:error, reason} -> {:error, reason}
        end
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
      description: "Captures a screenshot for visual verification.",
      parameters: [
        FunctionParam.new!(%{
          name: "simulator_uuid",
          type: :string,
          description: "The UUID of the simulator",
          required: true
        }),
        FunctionParam.new!(%{
          name: "file_name",
          type: :string,
          description: "File name for the screenshot (without extension)",
          required: true
        }),
        FunctionParam.new!(%{
          name: "title",
          type: :string,
          description: "Human-readable title describing what the screenshot shows",
          required: true
        })
      ],
      function: fn %{"simulator_uuid" => simulator_uuid, "file_name" => file_name, "title" => title}, _context ->
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
             :ok <-
               Client.create_screenshot(%{
                 file_name: file_name,
                 title: title,
                 server_url: server_url,
                 run_id: run_id,
                 auth_token: auth_token,
                 account_handle: account_handle,
                 project_handle: project_handle
               }) do
          base64_image = Base.encode64(image_data)
          {:ok, ContentPart.image!(base64_image, media: :png)}
        else
          {:error, reason} -> {:error, "Failed to capture screenshot: #{reason}"}
          {reason, _status} -> {:error, "Failed to capture screenshot: #{reason}"}
        end
      end
    })
  end

  defp step_finished_tool(%{
         server_url: server_url,
         run_id: run_id,
         auth_token: auth_token,
         account_handle: account_handle,
         project_handle: project_handle
       }) do
    Function.new!(%{
      name: "step_finished",
      description: "Marks a finished testing step. Use this tool often to mark your progress.",
      parameters: [
        FunctionParam.new!(%{
          name: "summary",
          type: :string,
          description: "Summary of the finished testing step",
          required: true
        }),
        FunctionParam.new!(%{
          name: "description",
          type: :string,
          description: "Detailed description of what was tested",
          required: true
        }),
        FunctionParam.new!(%{
          name: "issues",
          type: :array,
          item_type: "string",
          description: "List of issues encountered during the step",
          required: true
        })
      ],
      function: fn %{"summary" => summary, "description" => description, "issues" => issues} = _params, _llm_context ->
        Logger.debug("Finished step: #{summary}")

        case Client.create_step(%{
               summary: summary,
               description: description,
               issues: issues,
               server_url: server_url,
               run_id: run_id,
               auth_token: auth_token,
               account_handle: account_handle,
               project_handle: project_handle
             }) do
          :ok ->
            {:ok,
             "Step finished and reported. Screenshots have been associated with this step. Continue with your testing."}

          {:error, reason} ->
            {:error, "Failed to report step: #{reason}"}
        end
      end
    })
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
    for_result =
      for x <- 0..trunc(width)//grid_size,
          y <- 0..trunc(height)//grid_size,
          {:ok, point_info} <- [run_idb_describe_point(simulator_uuid, x, y)],
          {:ok, element} <- [JSON.decode(point_info)] do
        element
      end

    elements =
      Enum.uniq_by(for_result, fn element -> element["AXUniqueId"] || {element["frame"], element["AXLabel"]} end)

    {:ok, JSON.encode!(elements)}
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
    |> then(&if label = element["AXLabel"], do: Map.put(&1, "label", label), else: &1)
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
end
