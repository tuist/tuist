defmodule Tuist.QA.Tools do
  @moduledoc """
  QA tools such as for iOS Simulator interaction.
  """
  alias LangChain.Function
  alias LangChain.FunctionParam
  alias LangChain.Message.ContentPart

  require Logger

  def tools(context \\ %{}) do
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
      screenshot_tool(),
      step_finished_tool(context),
      finalize_tool(context)
    ]
  end

  defp describe_ui_tool do
    Function.new!(%{
      name: "describe_ui",
      description: "Retrieves the entire view hierarchy with precise frame coordinates for all visible elements",
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
          {:ok, content} -> {:ok, simplify_ui_description(content)}
          {:error, reason} -> {:error, reason}
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
        run_axe_command(simulator_uuid, ["ui", "long-press", "#{x}", "#{y}", "--duration", "#{duration}"])
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
        run_axe_command(simulator_uuid, ["type", text])
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
          description: "HID keycode to press",
          required: true
        })
      ],
      function: fn %{"simulator_uuid" => simulator_uuid, "keycode" => keycode} = _params, _context ->
        run_axe_command(simulator_uuid, ["key", keycode])
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

        run_axe_command(simulator_uuid, args)
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

        run_axe_command(simulator_uuid, args)
      end
    })
  end

  defp screenshot_tool do
    Function.new!(%{
      name: "screenshot",
      description: "Captures screenshot for visual verification. Optionally saves to a file path",
      parameters: [
        FunctionParam.new!(%{
          name: "simulator_uuid",
          type: :string,
          description: "The UUID of the simulator",
          required: true
        }),
        FunctionParam.new!(%{
          name: "file_path",
          type: :string,
          description: "Full path where to save the screenshot (e.g., /tmp/screenshots/test1.png)",
          required: false
        })
      ],
      function: fn %{"simulator_uuid" => simulator_uuid} = params, _context ->
        file_path =
          Map.get(params, "file_path")

        file_path =
          if is_nil(file_path) do
            {:ok, path} = Briefly.create()
            path
          else
            file_path
          end

        with {_, 0} <- System.cmd("xcrun", ["simctl", "io", simulator_uuid, "screenshot", file_path]),
             {:ok, image_data} <- File.read(file_path) do
          base64_image = Base.encode64(image_data)
          {:ok, ContentPart.image!(base64_image, media: :png)}
        else
          {:error, reason} -> {:error, "Failed to read screenshot file: #{reason}"}
          {error, _status} -> {:error, "Failed to capture screenshot: #{error}"}
        end
      end
    })
  end

  defp step_finished_tool(context) do
    Function.new!(%{
      name: "step_finished",
      description: "Marks a finished testing step. Call this often to mark your progress.",
      parameters: [
        FunctionParam.new!(%{
          name: "summary",
          type: :string,
          description: "Summary of the finished testing step",
          required: true
        })
      ],
      function: fn %{"summary" => summary} = _params, _llm_context ->
        server_url = Map.get(context, :server_url)
        run_id = Map.get(context, :run_id)
        auth_token = Map.get(context, :auth_token)

        create_step(summary, server_url, run_id, auth_token)
      end
    })
  end

  def create_step(summary, server_url, run_id, auth_token) do
    if server_url && run_id && auth_token do
      url = "#{server_url}/api/qa/runs/#{run_id}/steps"

      case Req.post(url,
             json: %{summary: summary},
             headers: [{"authorization", "Bearer #{auth_token}"}]
           ) do
        {:ok, %{status: status}} when status in 200..299 ->
          {:ok, "Step finished and reported. Continue with your testing."}

        {:ok, response} ->
          Logger.warning("Failed to report step: #{inspect(response)}")
          {:ok, "Step finished (reporting failed). Continue with your testing."}

        {:error, reason} ->
          Logger.warning("Failed to report step: #{inspect(reason)}")
          {:ok, "Step finished (reporting failed). Continue with your testing."}
      end
    else
      {:ok, "Step finished. Continue with your testing."}
    end
  end

  defp finalize_tool(context) do
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
        server_url = Map.get(context, :server_url)
        run_id = Map.get(context, :run_id)
        auth_token = Map.get(context, :auth_token)

        if server_url && run_id && auth_token do
          url = "#{server_url}/api/qa/runs/#{run_id}"

          case Req.patch(url,
                 json: %{status: "finished", summary: summary},
                 headers: [{"authorization", "Bearer #{auth_token}"}]
               ) do
            {:ok, %{status: status}} when status in 200..299 ->
              {:ok, "QA test run finished successfully and status updated."}

            {:ok, response} ->
              Logger.warning("Failed to update run status: #{inspect(response)}")
              {:ok, "QA test run finished (status update failed)."}

            {:error, reason} ->
              Logger.warning("Failed to update run status: #{inspect(reason)}")
              {:ok, "QA test run finished (status update failed)."}
          end
        else
          {:ok, "QA test run finished successfully."}
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
