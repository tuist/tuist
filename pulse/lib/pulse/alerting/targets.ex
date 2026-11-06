defmodule Pulse.Alerting.Targets do
  @moduledoc "Operator-provisioned notification bindings; only secret references enter object storage."
  alias Pulse.Alerting.{Canonical, Principal}
  alias Pulse.Runtime

  def validate(target) when is_map(target) do
    allowed = ~w(tenant id type secret_env)

    valid =
      Enum.all?([
        Map.keys(target) -- allowed == [],
        Principal.valid_id?(target["tenant"]),
        Principal.valid_id?(target["id"]),
        target["type"] == "slack_webhook",
        secret_name?(target["secret_env"])
      ])

    if valid, do: {:ok, target}, else: {:error, :invalid_target}
  end

  def validate(_), do: {:error, :invalid_target}

  def bind(tenant, ids) when is_list(ids) and length(ids) <= 8 do
    Enum.reduce_while(ids, {:ok, []}, &binding(tenant, &1, &2))
  end

  def bind(_, _), do: {:error, :invalid_target}

  def resolve(%{"version" => version} = binding) do
    descriptor = Map.delete(binding, "version")

    with {:ok, current} <- find(descriptor["tenant"], descriptor["id"]),
         true <- current == descriptor and Canonical.hash(current) == version,
         url when is_binary(url) <- Runtime.env(current["secret_env"]),
         true <- secure_url?(url) do
      {:ok, url}
    else
      _ -> {:error, :notification_target_unavailable}
    end
  end

  defp binding(tenant, id, {:ok, acc}) do
    case find(tenant, id) do
      {:ok, descriptor} -> {:cont, {:ok, acc ++ [Map.put(descriptor, "version", Canonical.hash(descriptor))]}}
      error -> {:halt, error}
    end
  end

  defp find(tenant, id) do
    env = Runtime.get_env(:pulse, Pulse.Alerting, [])

    case Enum.find(Keyword.get(env, :notification_targets, []), &(&1["tenant"] == tenant and &1["id"] == id)) do
      nil -> {:error, :invalid_target}
      target -> validate(target)
    end
  end

  defp secret_name?(value), do: is_binary(value) and Regex.match?(~r/\APULSE_ALERTING_[A-Z0-9_]{1,100}\z/, value)

  defp secure_url?(url) do
    uri = URI.parse(url)
    uri.scheme == "https" and is_binary(uri.host) and uri.host != "" and is_nil(uri.userinfo) and is_nil(uri.fragment)
  end
end
