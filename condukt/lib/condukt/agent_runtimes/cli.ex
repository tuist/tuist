defmodule Condukt.AgentRuntimes.CLI do
  @moduledoc false

  alias Condukt.Secrets

  @base_env %{
    "TERM" => "dumb",
    "PAGER" => "cat",
    "GIT_PAGER" => "cat"
  }

  @safe_env_vars ~w(PATH HOME USER LOGNAME HOSTNAME SHELL LANG LC_ALL LC_CTYPE TZ TMPDIR TMP TEMP)

  def run(command, args, context, opts) do
    timeout = Keyword.get_lazy(context.runtime_opts, :timeout, fn -> command_timeout(opts) end)

    case run_muontrap(command, args,
           cd: context.cwd,
           stderr_to_stdout: true,
           env: build_env(context.secrets, Keyword.get(context.runtime_opts, :env, [])),
           parallelism: false,
           timeout: timeout
         ) do
      {:ok, {_output, :timeout}} ->
        {:error, :timeout}

      {:ok, {output, 0}} ->
        {:ok, output}

      {:ok, {output, exit_code}} ->
        {:error, {:exit_status, exit_code, Secrets.redact_text(context.secrets, output)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp command_timeout(opts) do
    case Keyword.get(opts, :timeout) do
      timeout when is_integer(timeout) and timeout > 5_000 -> timeout - 5_000
      _ -> 295_000
    end
  end

  def final_output(raw_output, nil) do
    raw_output
    |> String.trim()
    |> ok_if_present()
  end

  def final_output(raw_output, output_path) do
    case File.read(output_path) do
      {:ok, output} ->
        output
        |> String.trim()
        |> ok_if_present()

      {:error, _reason} ->
        final_output(raw_output, nil)
    end
  end

  defp ok_if_present(""), do: {:error, :empty_response}
  defp ok_if_present(output), do: {:ok, output}

  defp run_muontrap(command, args, opts) do
    {:ok, MuonTrap.cmd("bash", ["-lc", "exec \"$@\" < /dev/null", "condukt-agent-runtime", command | args], opts)}
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

  defp build_env(secrets, overrides) do
    @safe_env_vars
    |> Enum.reduce(%{}, fn key, acc ->
      case System.get_env(key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
    |> Map.merge(@base_env)
    |> Map.merge(Map.new(Secrets.merge_env(secrets, overrides)))
    |> Enum.to_list()
  end
end
