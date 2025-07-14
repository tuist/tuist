defmodule Tuist.QAAgent.AxeTools do
  @moduledoc """
  Axe CLI tools for iOS Simulator interaction.
  Based on the XcodeBuildMCP implementation.
  """

  @type tool_definition :: %{
    name: String.t(),
    description: String.t(),
    input_schema: map(),
    function: function()
  }

  @type coordinate :: %{x: number(), y: number()}

  @doc """
  Returns all available axe tools for simulator interaction.
  """
  @spec get_tools() :: [tool_definition()]
  def get_tools do
    [
      describe_ui_tool(),
      tap_tool(),
      long_press_tool(),
      swipe_tool(),
      type_text_tool(),
      key_press_tool(),
      button_tool(),
      touch_tool(),
      gesture_tool()
    ]
  end

  defp describe_ui_tool do
    %{
      name: "describe_ui",
      description: "Retrieves the entire view hierarchy with precise frame coordinates for all visible elements",
      input_schema: %{
        type: "object",
        properties: %{
          simulator_uuid: %{type: "string", description: "The UUID of the iOS Simulator"}
        },
        required: ["simulator_uuid"]
      },
      function: &describe_ui/1
    }
  end

  defp tap_tool do
    %{
      name: "tap",
      description: "Simulates a tap at specific x, y coordinates",
      input_schema: %{
        type: "object",
        properties: %{
          simulator_uuid: %{type: "string", description: "The UUID of the iOS Simulator"},
          x: %{type: "number", description: "X coordinate to tap"},
          y: %{type: "number", description: "Y coordinate to tap"}
        },
        required: ["simulator_uuid", "x", "y"]
      },
      function: &tap/1
    }
  end

  defp long_press_tool do
    %{
      name: "long_press",
      description: "Performs a long press at coordinates with configurable duration",
      input_schema: %{
        type: "object",
        properties: %{
          simulator_uuid: %{type: "string", description: "The UUID of the iOS Simulator"},
          x: %{type: "number", description: "X coordinate to long press"},
          y: %{type: "number", description: "Y coordinate to long press"},
          duration: %{type: "number", description: "Duration in seconds", default: 1.0}
        },
        required: ["simulator_uuid", "x", "y"]
      },
      function: &long_press/1
    }
  end

  defp swipe_tool do
    %{
      name: "swipe",
      description: "Executes a swipe between two coordinate points",
      input_schema: %{
        type: "object",
        properties: %{
          simulator_uuid: %{type: "string", description: "The UUID of the iOS Simulator"},
          from_x: %{type: "number", description: "Starting X coordinate"},
          from_y: %{type: "number", description: "Starting Y coordinate"},
          to_x: %{type: "number", description: "Ending X coordinate"},
          to_y: %{type: "number", description: "Ending Y coordinate"},
          duration: %{type: "number", description: "Duration in seconds", default: 0.5}
        },
        required: ["simulator_uuid", "from_x", "from_y", "to_x", "to_y"]
      },
      function: &swipe/1
    }
  end

  defp type_text_tool do
    %{
      name: "type_text",
      description: "Types text using the US keyboard",
      input_schema: %{
        type: "object",
        properties: %{
          simulator_uuid: %{type: "string", description: "The UUID of the iOS Simulator"},
          text: %{type: "string", description: "Text to type"}
        },
        required: ["simulator_uuid", "text"]
      },
      function: &type_text/1
    }
  end

  defp key_press_tool do
    %{
      name: "key_press",
      description: "Presses a specific key by its HID keycode",
      input_schema: %{
        type: "object",
        properties: %{
          simulator_uuid: %{type: "string", description: "The UUID of the iOS Simulator"},
          keycode: %{type: "string", description: "HID keycode to press"}
        },
        required: ["simulator_uuid", "keycode"]
      },
      function: &key_press/1
    }
  end

  defp button_tool do
    %{
      name: "button",
      description: "Simulates hardware button presses (home, lock, side-button, etc.)",
      input_schema: %{
        type: "object",
        properties: %{
          simulator_uuid: %{type: "string", description: "The UUID of the iOS Simulator"},
          button: %{type: "string", description: "Button name (home, lock, side-button, volume-up, volume-down)"}
        },
        required: ["simulator_uuid", "button"]
      },
      function: &button/1
    }
  end

  defp touch_tool do
    %{
      name: "touch",
      description: "Provides granular touch down/up events",
      input_schema: %{
        type: "object",
        properties: %{
          simulator_uuid: %{type: "string", description: "The UUID of the iOS Simulator"},
          x: %{type: "number", description: "X coordinate"},
          y: %{type: "number", description: "Y coordinate"},
          action: %{type: "string", description: "Touch action (down, up, move)", default: "tap"}
        },
        required: ["simulator_uuid", "x", "y"]
      },
      function: &touch/1
    }
  end

  defp gesture_tool do
    %{
      name: "gesture",
      description: "Executes preset gesture patterns like scroll or edge swipes",
      input_schema: %{
        type: "object",
        properties: %{
          simulator_uuid: %{type: "string", description: "The UUID of the iOS Simulator"},
          gesture: %{type: "string", description: "Gesture type (scroll, edge-swipe)"},
          direction: %{type: "string", description: "Direction (up, down, left, right)"},
          x: %{type: "number", description: "X coordinate (optional)"},
          y: %{type: "number", description: "Y coordinate (optional)"}
        },
        required: ["simulator_uuid", "gesture"]
      },
      function: &gesture/1
    }
  end

  # Tool implementations
  defp describe_ui(%{"simulator_uuid" => simulator_uuid}) do
    case run_axe_command(simulator_uuid, ["describe-ui"]) do
      {:ok, output} -> {:ok, %{content: output}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp tap(%{"simulator_uuid" => simulator_uuid, "x" => x, "y" => y}) do
    case run_axe_command(simulator_uuid, ["tap", "-x", "#{x}", "-y", "#{y}"]) do
      {:ok, output} -> {:ok, %{content: "Tapped at (#{x}, #{y}): #{output}"}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp long_press(%{"simulator_uuid" => simulator_uuid, "x" => x, "y" => y} = params) do
    duration = Map.get(params, "duration", 1.0)
    case run_axe_command(simulator_uuid, ["ui", "long-press", "#{x}", "#{y}", "--duration", "#{duration}"]) do
      {:ok, output} -> {:ok, %{content: "Long pressed at (#{x}, #{y}) for #{duration}s: #{output}"}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp swipe(%{"simulator_uuid" => simulator_uuid, "from_x" => from_x, "from_y" => from_y, "to_x" => to_x, "to_y" => to_y} = params) do
    duration = Map.get(params, "duration", 0.5)
    case run_axe_command(simulator_uuid, ["ui", "swipe", "#{from_x}", "#{from_y}", "#{to_x}", "#{to_y}", "--duration", "#{duration}"]) do
      {:ok, output} -> {:ok, %{content: "Swiped from (#{from_x}, #{from_y}) to (#{to_x}, #{to_y}): #{output}"}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp type_text(%{"simulator_uuid" => simulator_uuid, "text" => text}) do
    case run_axe_command(simulator_uuid, ["ui", "type", text]) do
      {:ok, output} -> {:ok, %{content: "Typed text '#{text}': #{output}"}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp key_press(%{"simulator_uuid" => simulator_uuid, "keycode" => keycode}) do
    case run_axe_command(simulator_uuid, ["ui", "key", keycode]) do
      {:ok, output} -> {:ok, %{content: "Pressed key '#{keycode}': #{output}"}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp button(%{"simulator_uuid" => simulator_uuid, "button" => button_name}) do
    case run_axe_command(simulator_uuid, ["ui", "button", button_name]) do
      {:ok, output} -> {:ok, %{content: "Pressed button '#{button_name}': #{output}"}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp touch(%{"simulator_uuid" => simulator_uuid, "x" => x, "y" => y} = params) do
    action = Map.get(params, "action", "tap")
    case run_axe_command(simulator_uuid, ["ui", "touch", action, "#{x}", "#{y}"]) do
      {:ok, output} -> {:ok, %{content: "Touch #{action} at (#{x}, #{y}): #{output}"}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp gesture(%{"simulator_uuid" => simulator_uuid, "gesture" => gesture_type} = params) do
    args = ["ui", "gesture", gesture_type]
    args = case Map.get(params, "direction") do
      nil -> args
      direction -> args ++ ["--direction", direction]
    end

    args = case {Map.get(params, "x"), Map.get(params, "y")} do
      {nil, nil} -> args
      {x, y} -> args ++ ["--x", "#{x}", "--y", "#{y}"]
    end

    case run_axe_command(simulator_uuid, args) do
      {:ok, output} -> {:ok, %{content: "Executed gesture '#{gesture_type}': #{output}"}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_axe_command(simulator_uuid, args) do
    full_args = args ++ ["--udid", simulator_uuid]

    case System.cmd("/opt/homebrew/bin/axe", full_args, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, String.trim(output)}
      {error, status} ->
        {:error, "Axe command failed (status #{status}): #{error}"}
    end
  end
end
