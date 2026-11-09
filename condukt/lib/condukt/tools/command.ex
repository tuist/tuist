defmodule Condukt.Tools.Command do
  @moduledoc """
  Tool for executing one trusted command without shell parsing.

  This tool is parameterized. Each configured instance exposes a single
  executable such as `git`, `gh`, or `mix`, and accepts structured arguments as
  an array of strings. Environment variables are configured in trusted code via
  tool options rather than being provided by the model.
  """

  use Condukt.Tool

  alias Condukt.Secrets

  @max_lines 2000
  @max_bytes 50 * 1024
  @default_timeout 120_000
  @base_env %{
    "TERM" => "dumb",
    "PAGER" => "cat",
    "GIT_PAGER" => "cat"
  }
  @safe_env_vars ~w(PATH HOME USER LOGNAME HOSTNAME SHELL LANG LC_ALL LC_CTYPE TZ TMPDIR TMP TEMP)

  @impl true
  def name(opts) do
    Keyword.get_lazy(opts, :name, fn ->
      opts
      |> Keyword.fetch!(:command)
      |> Path.basename()
      |> Macro.camelize()
    end)
  end

  @impl true
  def description(opts) do
    Keyword.get(
      opts,
      :description,
      """
      Execute the trusted `#{Keyword.fetch!(opts, :command)}` command without shell parsing.
      Pass arguments as an array of strings. Output is truncated to #{@max_lines} lines or
      #{div(@max_bytes, 1024)}KB. Environment variables come from trusted tool configuration,
      not from the model.
      """
      |> String.trim()
    )
  end

  @impl true
  def parameters(_opts) do
    %{
      type: "object",
      properties: %{
        args: %{
          type: "array",
          items: %{type: "string"},
          description: "Arguments to pass to the configured command"
        },
        cwd: %{
          type: "string",
          description: "Directory to run the command in (relative or absolute)"
        },
        timeout: %{
          type: "number",
          description: "Timeout in seconds (optional, default: #{div(@default_timeout, 1000)})"
        }
      }
    }
  end

  @impl true
  def call(args, context) do
    with {:ok, command_args} <- normalize_args(args["args"] || []),
         {:ok, command} <- fetch_command(context.opts) do
      base_cwd = context[:cwd] || File.cwd!()
      cwd = resolve_cwd(args["cwd"], base_cwd)
      timeout = trunc((args["timeout"] || div(@default_timeout, 1000)) * 1000)
      env = build_env(Secrets.merge_env(context[:secrets], Keyword.get(context.opts, :env, [])))

      case execute_command(command, command_args, cwd, timeout, env) do
        {:ok, output, exit_code} ->
          {:ok, format_result(output, exit_code)}

        {:error, :timeout} ->
          {:error, "Command timed out after #{div(timeout, 1000)} seconds"}

        {:error, reason} ->
          {:error, "Command failed: #{reason}"}
      end
    end
  end

  defp fetch_command(opts) do
    case Keyword.fetch(opts, :command) do
      {:ok, command} when is_binary(command) and command != "" -> {:ok, command}
      _ -> {:error, "Command tool requires a :command option"}
    end
  end

  defp normalize_args(args) when is_list(args) do
    if Enum.all?(args, &is_binary/1) do
      {:ok, args}
    else
      {:error, "Command arguments must be an array of strings"}
    end
  end

  defp normalize_args(_), do: {:error, "Command arguments must be an array of strings"}

  defp resolve_cwd(nil, cwd), do: cwd

  defp resolve_cwd(path, cwd) do
    if Path.type(path) == :absolute do
      path
    else
      Path.expand(path, cwd)
    end
  end

  defp execute_command(command, args, cwd, timeout, env) do
    case run_muontrap(command, args,
           cd: cwd,
           stderr_to_stdout: true,
           env: env,
           parallelism: false,
           timeout: timeout
         ) do
      {:ok, {_output, :timeout}} -> {:error, :timeout}
      {:ok, {output, exit_code}} -> {:ok, output, exit_code}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_muontrap(command, args, opts) do
    {:ok, MuonTrap.cmd(command, args, opts)}
  catch
    :error, error -> {:error, format_error(error)}
  end

  defp format_error(error) do
    if is_exception(error) do
      Exception.message(error)
    else
      inspect(error)
    end
  end

  defp build_env(overrides) do
    @safe_env_vars
    |> Enum.reduce(%{}, fn key, acc ->
      case System.get_env(key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
    |> Map.merge(@base_env)
    |> Map.merge(normalize_env(overrides))
    |> Enum.to_list()
  end

  defp normalize_env(env) when is_map(env) do
    Map.new(env, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp normalize_env(env) when is_list(env) do
    Map.new(env, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp normalize_env(_), do: %{}

  defp format_result(output, exit_code) do
    {truncated_output, truncated?} = truncate_output(output)

    [
      truncated_output,
      truncated? && "(output truncated)",
      exit_code != 0 && "(exit code: #{exit_code})"
    ]
    |> Enum.reject(&(&1 in [false, nil, ""]))
    |> Enum.join("\n\n")
  end

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
