defmodule Runner.Runner.SSH do
  @moduledoc """
  SSH client for executing commands and transferring files to VMs.
  Uses SSH key-based authentication.
  """

  require Logger

  @default_port 22
  @default_timeout_ms 60_000
  @ssh_options [
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-o", "LogLevel=ERROR",
    "-o", "ConnectTimeout=10"
  ]

  @type ssh_opts :: [
    port: integer(),
    timeout_ms: integer()
  ]

  @doc """
  Executes a command via SSH and returns the output and exit code.

  ## Options
    - `:port` - SSH port (default: 22)
    - `:timeout_ms` - Command timeout in milliseconds (default: 60000)
  """
  @spec exec(String.t(), String.t(), String.t(), String.t(), ssh_opts()) ::
          {:ok, String.t(), integer()} | {:error, term()}
  def exec(host, user, key_path, command, opts \\ []) do
    port = Keyword.get(opts, :port, @default_port)
    _timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    expanded_key_path = Path.expand(key_path)

    unless File.exists?(expanded_key_path) do
      {:error, {:key_not_found, expanded_key_path}}
    else
      args = build_ssh_args(host, port, user, expanded_key_path, command)

      Logger.debug("SSH exec: ssh #{Enum.join(args, " ")}")

      case System.cmd("ssh", args, stderr_to_stdout: true) do
        {output, exit_code} ->
          {:ok, output, exit_code}
      end
    end
  rescue
    e ->
      {:error, {:ssh_error, Exception.message(e)}}
  end

  @doc """
  Executes a command via SSH with streaming output.

  The output_callback function is called for each chunk of output received.
  Returns the exit code when the command completes.

  ## Options
    - `:port` - SSH port (default: 22)
    - `:timeout_ms` - Command timeout in milliseconds (default: 3600000 - 1 hour)
  """
  @spec exec_stream(String.t(), String.t(), String.t(), String.t(), (String.t() -> any()), ssh_opts()) ::
          {:ok, integer()} | {:error, term()}
  def exec_stream(host, user, key_path, command, output_callback, opts \\ []) do
    port = Keyword.get(opts, :port, @default_port)
    timeout_ms = Keyword.get(opts, :timeout_ms, 3_600_000)

    expanded_key_path = Path.expand(key_path)

    unless File.exists?(expanded_key_path) do
      {:error, {:key_not_found, expanded_key_path}}
    else
      args = build_ssh_args(host, port, user, expanded_key_path, command)

      Logger.info("SSH exec_stream: ssh #{host} -p #{port}")
      Logger.debug("Command: #{command}")

      port_ref = Port.open(
        {:spawn_executable, System.find_executable("ssh")},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          {:args, args}
        ]
      )

      collect_streaming_output(port_ref, output_callback, timeout_ms)
    end
  rescue
    e ->
      {:error, {:ssh_error, Exception.message(e)}}
  end

  @doc """
  Copies a local file to the remote host via SCP.

  ## Options
    - `:port` - SSH port (default: 22)
    - `:timeout_ms` - Transfer timeout in milliseconds (default: 300000 - 5 min)
  """
  @spec copy_to(String.t(), String.t(), String.t(), String.t(), String.t(), ssh_opts()) ::
          :ok | {:error, term()}
  def copy_to(host, user, key_path, local_path, remote_path, opts \\ []) do
    port = Keyword.get(opts, :port, @default_port)
    _timeout_ms = Keyword.get(opts, :timeout_ms, 300_000)

    expanded_key_path = Path.expand(key_path)

    unless File.exists?(expanded_key_path) do
      {:error, {:key_not_found, expanded_key_path}}
    else
      unless File.exists?(local_path) do
        {:error, {:local_file_not_found, local_path}}
      else
        args = build_scp_args(port, expanded_key_path) ++ [
          local_path,
          "#{user}@#{host}:#{remote_path}"
        ]

        Logger.debug("SCP to remote: scp #{Enum.join(args, " ")}")

        case System.cmd("scp", args, stderr_to_stdout: true) do
          {_output, 0} -> :ok
          {output, exit_code} -> {:error, {:scp_failed, exit_code, output}}
        end
      end
    end
  rescue
    e ->
      {:error, {:scp_error, Exception.message(e)}}
  end

  @doc """
  Copies a file from the remote host to local via SCP.

  ## Options
    - `:port` - SSH port (default: 22)
    - `:timeout_ms` - Transfer timeout in milliseconds (default: 300000 - 5 min)
  """
  @spec copy_from(String.t(), String.t(), String.t(), String.t(), String.t(), ssh_opts()) ::
          :ok | {:error, term()}
  def copy_from(host, user, key_path, remote_path, local_path, opts \\ []) do
    port = Keyword.get(opts, :port, @default_port)
    _timeout_ms = Keyword.get(opts, :timeout_ms, 300_000)

    expanded_key_path = Path.expand(key_path)

    unless File.exists?(expanded_key_path) do
      {:error, {:key_not_found, expanded_key_path}}
    else
      # Ensure local directory exists
      local_dir = Path.dirname(local_path)
      File.mkdir_p!(local_dir)

      args = build_scp_args(port, expanded_key_path) ++ [
        "#{user}@#{host}:#{remote_path}",
        local_path
      ]

      Logger.debug("SCP from remote: scp #{Enum.join(args, " ")}")

      case System.cmd("scp", args, stderr_to_stdout: true) do
        {_output, 0} -> :ok
        {output, exit_code} -> {:error, {:scp_failed, exit_code, output}}
      end
    end
  rescue
    e ->
      {:error, {:scp_error, Exception.message(e)}}
  end

  @doc """
  Checks if SSH connection to host is available.

  ## Options
    - `:port` - SSH port (default: 22)
    - `:timeout_ms` - Connection timeout in milliseconds (default: 5000)
  """
  @spec check_connection(String.t(), String.t(), String.t(), ssh_opts()) ::
          :ok | {:error, term()}
  def check_connection(host, user, key_path, opts \\ []) do
    port = Keyword.get(opts, :port, @default_port)

    case exec(host, user, key_path, "echo ok", port: port, timeout_ms: 10_000) do
      {:ok, output, 0} ->
        if String.contains?(output, "ok") do
          :ok
        else
          {:error, :unexpected_response}
        end

      {:ok, _output, exit_code} ->
        {:error, {:connection_failed, exit_code}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp build_ssh_args(host, port, user, key_path, command) do
    @ssh_options ++ [
      "-i", key_path,
      "-p", to_string(port),
      "#{user}@#{host}",
      command
    ]
  end

  defp build_scp_args(port, key_path) do
    [
      "-o", "StrictHostKeyChecking=no",
      "-o", "UserKnownHostsFile=/dev/null",
      "-o", "LogLevel=ERROR",
      "-i", key_path,
      "-P", to_string(port)
    ]
  end

  defp collect_streaming_output(port, output_callback, timeout_ms) do
    receive do
      {^port, {:data, data}} ->
        output_callback.(data)
        collect_streaming_output(port, output_callback, timeout_ms)

      {^port, {:exit_status, status}} ->
        {:ok, status}
    after
      timeout_ms ->
        Port.close(port)
        {:error, :timeout}
    end
  end
end
