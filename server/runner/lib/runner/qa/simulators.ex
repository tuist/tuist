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
    launch_arguments = String.replace(launch_arguments, "\"", "") |> String.split(" ")

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

  Returns `{:ok, pid}` with the recording process PID on success or `{:error, reason}` on failure.
  """
  def start_recording(%SimulatorDevice{udid: device_udid}, output_path) do
    # Use Port directly since MuonTrap has issues with the recording command
    port =
      Port.open({:spawn_executable, System.find_executable("xcrun")}, [
        :binary,
        :stderr_to_stdout,
        :exit_status,
        args: ["simctl", "io", device_udid, "recordVideo", output_path, "--force"]
      ])

    case port do
      port when is_port(port) ->
        # Store the output path and port for later reference
        Process.put({:recording_port, port}, output_path)
        IO.puts("Recording started for simulator #{device_udid} to #{output_path}")
        # Give the recording a moment to start
        :timer.sleep(1000)
        {:ok, port}

      error ->
        {:error, "Failed to start recording: #{inspect(error)}"}
    end
  end

  @doc """
  Stops a recording that was started with start_recording/2.

  Parameters:
    - port: The Port returned by start_recording/2

  Returns `:ok` on success.
  """
  def stop_recording(port) when is_port(port) do
    # Get the OS process ID from the port
    case :erlang.port_info(port, :os_pid) do
      {:os_pid, os_pid} ->
        IO.puts("Sending SIGINT to recording process (OS PID: #{os_pid})")

        # Send SIGINT to the xcrun process to gracefully stop recording
        case System.cmd("kill", ["-INT", Integer.to_string(os_pid)]) do
          {_output, 0} ->
            IO.puts("SIGINT sent successfully")

          {output, exit_code} ->
            IO.puts("Failed to send SIGINT: #{output}, exit code: #{exit_code}")
        end

        # Wait for the process to finish and collect output
        result = receive_port_data(port, "", 10_000)

        # Close port if it's still open
        try do
          Port.close(port)
        catch
          # Port already closed
          :error, :badarg -> :ok
        end

        IO.puts("Recording process output:")
        IO.puts(result)

        # Check if the video file was created and has content
        recording_path = get_recording_path_from_port(port)

        case File.stat(recording_path) do
          {:ok, %{size: size}} when size > 0 ->
            IO.puts("Recording file created successfully at #{recording_path} (#{size} bytes)")

          {:ok, %{size: 0}} ->
            IO.puts("Warning: Recording file is empty at #{recording_path}")

          {:error, reason} ->
            IO.puts("Warning: Recording file not found at #{recording_path}: #{inspect(reason)}")
        end

        :ok

      error ->
        IO.puts("Could not get OS PID: #{inspect(error)}")
        :ok
    end
  end

  # Helper function to get recording path from port
  defp get_recording_path_from_port(port) do
    Process.get({:recording_port, port}, "/tmp/unknown_recording.mov")
  end

  defp receive_port_data(port, acc, timeout) do
    receive do
      {^port, {:data, data}} ->
        new_acc = acc <> data
        receive_port_data(port, new_acc, timeout)

      {^port, {:exit_status, status}} ->
        IO.puts("Port exited with status: #{status}")
        acc
    after
      timeout ->
        IO.puts("Port receive timeout")
        acc
    end
  end
end
