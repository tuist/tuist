defmodule Condukt.Secrets.Providers.OnePassword do
  @moduledoc """
  Loads a session secret from 1Password CLI secret references.

  The provider shells out to `op read <ref>` during session initialization.
  Authenticate `op` before starting the session, or provide an
  `OP_SERVICE_ACCOUNT_TOKEN` in the host process environment.

      MyApp.Agent.start_link(
        secrets: [
          GH_TOKEN: {:one_password, "op://Engineering/GitHub/token"}
        ]
      )

  Options:

  - `:ref` is the 1Password secret reference. Required.
  - `:command` is the executable to run. Defaults to `"op"`.
  - `:account` passes `--account` to `op`.
  - `:timeout` is the command timeout in milliseconds. Defaults to `30_000`.
  - `:env` is a trusted environment override list passed to `op`.
  """

  @behaviour Condukt.SecretProvider

  @default_timeout 30_000
  @safe_env_vars ~w(
    PATH HOME USER LOGNAME SHELL LANG LC_ALL LC_CTYPE TZ TMPDIR TMP TEMP
    OP_ACCOUNT OP_BIOMETRIC_UNLOCK_ENABLED OP_CACHE OP_CONFIG_DIR
    OP_CONNECT_HOST OP_CONNECT_TOKEN OP_DEBUG OP_FORMAT OP_INCLUDE_ARCHIVE
    OP_ISO_TIMESTAMPS OP_RUN_NO_MASKING OP_SESSION OP_SERVICE_ACCOUNT_TOKEN
  )

  @impl Condukt.SecretProvider
  def load(opts) do
    with {:ok, ref} <- fetch_ref(opts) do
      command = Keyword.get(opts, :command, "op")
      timeout = Keyword.get(opts, :timeout, @default_timeout)
      env = Keyword.get(opts, :env, [])
      args = build_args(ref, opts)

      case MuonTrap.cmd(command, args,
             stderr_to_stdout: true,
             env: build_env(env),
             parallelism: false,
             timeout: timeout
           ) do
        {output, 0} -> {:ok, String.trim_trailing(output, "\n")}
        {_output, :timeout} -> {:error, :one_password_timeout}
        {output, exit_code} -> {:error, {:one_password_failed, exit_code, String.trim(output)}}
      end
    end
  end

  defp fetch_ref(opts) do
    case Keyword.fetch(opts, :ref) do
      {:ok, ref} when is_binary(ref) and ref != "" -> {:ok, ref}
      _ -> {:error, :one_password_secret_requires_ref}
    end
  end

  defp build_args(ref, opts) do
    ["read", ref]
    |> append_account(opts[:account])
  end

  defp append_account(args, nil), do: args
  defp append_account(args, account), do: args ++ ["--account", to_string(account)]

  defp build_env(overrides) do
    @safe_env_vars
    |> Enum.reduce(%{}, fn key, acc ->
      case System.get_env(key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
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
end
