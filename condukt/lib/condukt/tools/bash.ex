defmodule Condukt.Tools.Bash do
  @moduledoc """
  Tool for executing bash commands.

  Routes through the active `Condukt.Sandbox`. With `Sandbox.Local` this
  spawns a real bash subprocess on the host; with `Sandbox.Virtual` it runs
  inside the in-memory bashkit interpreter with no host process spawning; with
  `Sandbox.Microsandbox` it executes inside the guest microVM.

  Output is truncated to reasonable limits.

  ## Parameters

  - `command` - The bash command to execute
  - `cwd` - Directory to run the command in (optional, relative to the sandbox's cwd)
  - `timeout` - Timeout in seconds (optional, default: 120)
  """

  use Condukt.Tool

  alias Condukt.{Sandbox, Secrets}

  @max_lines 2000
  @max_bytes 50 * 1024
  @default_timeout 120_000

  @impl true
  def name, do: "Bash"

  @impl true
  def description do
    """
    Execute a bash command in the current working directory. Returns combined stdout/stderr.
    Output is truncated to #{@max_lines} lines or #{div(@max_bytes, 1024)}KB.
    Optionally provide a cwd and timeout in seconds.
    """
    |> String.trim()
  end

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        command: %{
          type: "string",
          description: "Bash command to execute"
        },
        cwd: %{
          type: "string",
          description: "Directory to run the command in (relative or absolute)"
        },
        timeout: %{
          type: "number",
          description: "Timeout in seconds (optional, default: #{div(@default_timeout, 1000)})"
        }
      },
      required: ["command"]
    }
  end

  @impl true
  def call(%{"command" => command} = args, context) do
    sandbox = fetch_sandbox!(context)
    timeout = trunc((args["timeout"] || div(@default_timeout, 1000)) * 1000)

    exec_opts =
      []
      |> put_if_present(:cwd, args["cwd"])
      |> put_if_present(:env, Secrets.env(context[:secrets]))
      |> Keyword.put(:timeout, timeout)

    case Sandbox.exec(sandbox, command, exec_opts) do
      {:ok, %{output: output, exit_code: exit_code}} ->
        {truncated, truncated?} = truncate_output(output)

        {:ok,
         [
           truncated,
           truncated? && "(output truncated)",
           exit_code != 0 && "(exit code: #{exit_code})"
         ]
         |> Enum.reject(&(&1 in [false, nil, ""]))
         |> Enum.join("\n\n")}

      {:error, :timeout} ->
        {:error, "Command timed out after #{div(timeout, 1000)} seconds"}

      {:error, reason} ->
        {:error, "Command failed: #{inspect(reason)}"}
    end
  end

  defp fetch_sandbox!(%{sandbox: %Sandbox{} = sandbox}), do: sandbox

  defp fetch_sandbox!(_) do
    raise ArgumentError,
          "Condukt.Tools.Bash requires context.sandbox. " <>
            "When invoking the tool outside a Session, build one with " <>
            "Condukt.Sandbox.new(Condukt.Sandbox.Local, cwd: \"...\")."
  end

  defp put_if_present(opts, _key, nil), do: opts
  defp put_if_present(opts, key, value), do: Keyword.put(opts, key, value)

  defp truncate_output(output) do
    lines = String.split(output, "\n")

    {lines, truncated_by_lines?} =
      if length(lines) > @max_lines do
        {Enum.take(lines, @max_lines), true}
      else
        {lines, false}
      end

    content = Enum.join(lines, "\n")

    {content, truncated_by_bytes?} =
      if byte_size(content) > @max_bytes do
        {String.slice(content, 0, @max_bytes), true}
      else
        {content, false}
      end

    {content, truncated_by_lines? or truncated_by_bytes?}
  end
end
