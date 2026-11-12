defmodule Condukt.Secrets do
  @moduledoc """
  Session-scoped secrets for agent tool execution.

  `Condukt.Secrets` resolves trusted secret declarations into environment
  variables while a session starts. The resolved values are not added to the
  system prompt, user messages, or persisted session snapshots. Built-in tools
  receive them through their execution environment when they spawn commands.

  ## Secret declarations

  Configure secrets as a map or keyword list whose keys are the environment
  variable names exposed to tools:

      MyApp.Agent.start_link(
        secrets: [
          GH_TOKEN: {:one_password, "op://Engineering/GitHub/token"},
          DATABASE_URL: {:env, "DATABASE_URL"}
        ]
      )

  The built-in provider aliases are:

  - `:one_password` or `:op` for `Condukt.Secrets.Providers.OnePassword`
  - `:env` for `Condukt.Secrets.Providers.Env`
  - `:static` for `Condukt.Secrets.Providers.Static`

  Custom providers can be used directly:

      secrets: [
        API_TOKEN: {MyApp.Secrets.Vault, path: "agents/api-token"}
      ]

  Later declarations for the same environment variable replace earlier ones.

  ## Redaction

  Resolved secret values are exact-match redacted from tool results before they
  are stored in the session history or sent back to the model. They are also
  redacted from outbound user and tool messages as a final guard.
  """

  alias Condukt.Redactor
  alias Condukt.Redactors
  alias Condukt.Secrets.Providers

  defstruct env: []

  @provider_aliases %{
    env: Providers.Env,
    one_password: Providers.OnePassword,
    op: Providers.OnePassword,
    static: Providers.Static
  }

  @env_name_pattern ~r/^[A-Za-z_][A-Za-z0-9_]*$/

  @doc """
  Returns an empty secrets container.
  """
  def empty, do: %__MODULE__{}

  @doc """
  Resolves a user-supplied secret declaration into a secrets container.
  """
  def resolve(nil), do: {:ok, empty()}
  def resolve(%__MODULE__{} = secrets), do: {:ok, secrets}

  def resolve(specs) when is_map(specs) do
    specs
    |> Map.to_list()
    |> resolve()
  end

  def resolve(specs) when is_list(specs) do
    Enum.reduce_while(specs, {:ok, empty()}, fn entry, {:ok, secrets} ->
      case resolve_entry(entry) do
        {:ok, name, value} ->
          {:cont, {:ok, put_env(secrets, name, value)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  def resolve(other), do: {:error, {:invalid_secrets, other}}

  @doc """
  Returns resolved environment variables as `{name, value}` tuples.
  """
  def env(nil), do: []
  def env(%__MODULE__{env: env}), do: env

  @doc """
  Returns resolved secret environment variable names without values.
  """
  def names(nil), do: []

  def names(%__MODULE__{} = secrets) do
    secrets
    |> env()
    |> Enum.map(fn {name, _value} -> name end)
  end

  @doc """
  Merges trusted environment overrides with session secrets.

  Session secrets win when the same variable is present in both places.
  """
  def merge_env(secrets, overrides \\ []) do
    overrides
    |> normalize_env()
    |> Map.merge(Map.new(env(secrets)))
    |> Enum.to_list()
  end

  @doc """
  Returns a redactor spec for the resolved secrets.

  The returned spec can be composed with any other `Condukt.Redactor` spec.
  Returns `nil` when there are no resolved secrets.
  """
  def redactor(nil), do: nil
  def redactor(%__MODULE__{env: []}), do: nil
  def redactor(%__MODULE__{} = secrets), do: {Redactors.Secrets, secrets: secrets}

  @doc """
  Redacts resolved secret values from outbound messages.
  """
  def redact_messages(secrets, messages), do: Redactor.redact_messages(redactor(secrets), messages)

  @doc """
  Redacts resolved secret values from a tool result before it is stored.
  """
  def redact_result(nil, result), do: result
  def redact_result(%__MODULE__{env: []}, result), do: result
  def redact_result(%__MODULE__{} = secrets, result), do: redact_value(secrets, result)

  @doc """
  Redacts resolved secret values from a binary.
  """
  def redact_text(nil, text), do: text
  def redact_text(%__MODULE__{env: []}, text), do: text

  def redact_text(%__MODULE__{} = secrets, text) when is_binary(text) do
    Redactor.apply(redactor(secrets), text)
  end

  defp resolve_entry({name, source}) do
    with {:ok, env_name} <- normalize_env_name(name),
         {:ok, provider, opts} <- normalize_source(source),
         {:ok, value} <- provider.load(opts) do
      {:ok, env_name, value}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_secret_provider_result, other}}
    end
  end

  defp resolve_entry(other), do: {:error, {:invalid_secret_entry, other}}

  defp normalize_env_name(name) when is_atom(name), do: normalize_env_name(Atom.to_string(name))

  defp normalize_env_name(name) when is_binary(name) do
    if Regex.match?(@env_name_pattern, name) do
      {:ok, name}
    else
      {:error, {:invalid_secret_env_name, name}}
    end
  end

  defp normalize_env_name(other), do: {:error, {:invalid_secret_env_name, other}}

  defp normalize_source({provider, opts}) when is_atom(provider) and is_list(opts) do
    with {:ok, provider} <- provider_module(provider) do
      {:ok, provider, opts}
    end
  end

  defp normalize_source({provider, value}) when is_atom(provider) do
    with {:ok, provider_module} <- provider_module(provider) do
      {:ok, provider_module, provider_value_opts(provider, value)}
    end
  end

  defp normalize_source(other), do: {:error, {:invalid_secret_source, other}}

  defp provider_module(alias) when is_map_key(@provider_aliases, alias), do: {:ok, Map.fetch!(@provider_aliases, alias)}

  defp provider_module(module) when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        if function_exported?(module, :load, 1) do
          {:ok, module}
        else
          {:error, {:unknown_secret_provider, module}}
        end

      {:error, _reason} ->
        {:error, {:unknown_secret_provider, module}}
    end
  end

  defp provider_value_opts(provider, value) when provider in [:one_password, :op], do: [ref: value]
  defp provider_value_opts(:env, value), do: [name: value]
  defp provider_value_opts(:static, value), do: [value: value]
  defp provider_value_opts(_provider, value), do: [value: value]

  defp put_env(%__MODULE__{} = secrets, name, value) do
    env =
      secrets.env
      |> Enum.reject(fn {existing, _} -> existing == name end)
      |> then(&[{name, value} | &1])

    %{secrets | env: env}
  end

  defp normalize_env(env) when is_map(env) do
    Map.new(env, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp normalize_env(env) when is_list(env) do
    Map.new(env, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp normalize_env(_), do: %{}

  defp redact_value(secrets, value) when is_binary(value), do: redact_text(secrets, value)

  defp redact_value(secrets, values) when is_list(values) do
    Enum.map(values, &redact_value(secrets, &1))
  end

  defp redact_value(secrets, value) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {key, inner} -> {key, redact_value(secrets, inner)} end)
  end

  defp redact_value(_secrets, value), do: value
end
