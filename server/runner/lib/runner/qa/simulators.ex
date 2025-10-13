defmodule Runner.QA.Simulators do
  @moduledoc """
  Module for interacting with simulators via xcrun simctl.
  """

  alias Runner.QA.Simulators.SimulatorDevice

  @doc """
  Lists all available simulator devices.

  Options:
    - runtime_identifier: Filter devices by runtime identifier (e.g. "com.apple.CoreSimulator.SimRuntime.iOS-18-4")
    - name: Filter devices by name (e.g. "iPhone 16")

  Returns an array of `SimulatorDevice`.
  """
  def devices(opts \\ []) do
    runtime_identifier = Keyword.get(opts, :runtime_identifier)
    name = Keyword.get(opts, :name)

    with {output, 0} <- System.cmd("xcrun", ["simctl", "list", "devices", "--json"]),
         {:ok, %{"devices" => devices_by_runtime}} <- JSON.decode(output) do
      devices =
        devices_by_runtime
        |> Enum.flat_map(&parse_devices_for_runtime/1)
        |> filter_by_name(name)
        |> filter_by_runtime_identifier(runtime_identifier)

      {:ok, devices}
    else
      {:error, reason} ->
        {:error, "Failed to parse JSON: #{reason}"}

      {output, _exit_code} ->
        {:error, "Listing devices failed with: #{output}"}
    end
  end

  defp parse_devices_for_runtime({runtime_identifier, devices}) do
    Enum.map(devices, &parse_device(&1, runtime_identifier))
  end

  defp parse_device(%{"name" => name, "udid" => udid, "state" => state}, runtime_identifier) do
    %SimulatorDevice{
      name: name,
      udid: udid,
      state: state,
      runtime_identifier: runtime_identifier
    }
  end

  defp filter_by_runtime_identifier(devices, nil), do: devices

  defp filter_by_runtime_identifier(devices, runtime_identifier) do
    Enum.filter(devices, &(&1.runtime_identifier == runtime_identifier))
  end

  defp filter_by_name(devices, nil), do: devices

  defp filter_by_name(devices, name) do
    Enum.filter(devices, &(&1.name == name))
  end

  @doc """
  Boots a simulator device if it's not already booted.

  Parameters:
    - device: SimulatorDevice struct

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  def boot_simulator(%SimulatorDevice{state: "Booted"}), do: :ok

  def boot_simulator(%SimulatorDevice{udid: device_udid}) do
    case System.cmd("xcrun", ["simctl", "boot", device_udid]) do
      {_output, 0} ->
        :ok

      {output, _exit_code} ->
        {:error, "Failed to boot simulator: #{output}"}
    end
  end

  @doc """
  Installs an app on a simulator device.

  Parameters:
    - app_path: Path to the .app bundle to install
    - device: SimulatorDevice struct

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  def install_app(app_path, %SimulatorDevice{udid: device_udid}) do
    case System.cmd("xcrun", ["simctl", "install", device_udid, app_path]) do
      {_output, 0} ->
        :ok

      {output, _exit_code} ->
        {:error, "Failed to install app: #{output}"}
    end
  end

  @doc """
  Launches an app on a simulator device.

  Parameters:
    - bundle_identifier: Bundle identifier of the app to launch
    - device: SimulatorDevice struct
    - launch_arguments: Optional string of launch arguments (default: "")

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  def launch_app(bundle_identifier, %SimulatorDevice{udid: device_udid}, launch_arguments \\ "") do
    launch_arguments = launch_arguments |> String.replace("\"", "") |> String.split(" ")

    args =
      ["simctl", "launch", device_udid, bundle_identifier] ++ launch_arguments

    case System.cmd("xcrun", args) do
      {_output, 0} ->
        :ok

      {output, _exit_code} ->
        {:error, "Failed to launch app: #{output}"}
    end
  end

  @doc """
  Starts recording video from a simulator device.

  Parameters:
    - device: SimulatorDevice struct
    - output_path: Path where the video file will be saved
  """
  def start_recording(%SimulatorDevice{udid: device_udid}, output_path) do
    cmd =
      "/opt/homebrew/bin/axe stream-video --udid #{device_udid} --fps 30 --format ffmpeg | ffmpeg -y -loglevel quiet -f image2pipe -framerate 30 -i - -vf \"scale=1178:2556\" -c:v libx264 -preset ultrafast -pix_fmt yuv420p -movflags +faststart -f mp4 \"#{output_path}\""

    Port.open({:spawn_executable, System.find_executable("sh")}, [
      :binary,
      :exit_status,
      args: ["-c", cmd]
    ])
  end

  @doc """
  Stops a recording that was started with start_recording/2.

  Parameters:
    - port: The Port returned by start_recording/2

  Returns `:ok` on success.
  """
  def stop_recording(port) when is_port(port) do
    # Get the OS process ID from the port
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} ->
        case System.cmd("kill", ["-TERM", "-#{Integer.to_string(os_pid)}"]) do
          {_output, 0} ->
            Port.close(port)
            :ok

          {output, exit_code} ->
            {:error, "Failed to stop recording due to exit code #{exit_code}. Output: #{output}"}
        end

      error ->
        {:error, "Failed to get OS PID: #{inspect(error)}"}
    end
  end
end
