defmodule Pulse.Alerting.Principal do
  @moduledoc "Capability-scoped alerting identities from operator configuration, not caller assertions."

  alias Pulse.Auth.Issuer
  alias Pulse.Runtime

  # The only capabilities alerting authorizes. Configured principals, issuer
  # scopes and `authorize/3` all read this list so they cannot drift apart.
  @capabilities ~w(alert:read alert:rules:write alert:audit:read alert:preview alert:evaluate alert:import alert:record)

  def capabilities, do: @capabilities

  @doc """
  Parses `PULSE_ALERTING_PRINCIPALS_JSON` (called from `config/runtime.exs`),
  raising on any invalid, unknown-capability or duplicate principal.
  """
  def parse_configured!(json) do
    principals =
      case JSON.decode(json) do
        {:ok, values} when is_list(values) and length(values) <= 256 -> Enum.map(values, &parse_configured_one!/1)
        _ -> raise "PULSE_ALERTING_PRINCIPALS_JSON must be a JSON array of at most 256 principals"
      end

    for key <- [&{&1.tenant, &1.id}, & &1.token_hash] do
      keys = Enum.map(principals, key)

      if length(Enum.uniq(keys)) != length(keys),
        do: raise("PULSE_ALERTING_PRINCIPALS_JSON has duplicate identities or credentials")
    end

    principals
  end

  defp parse_configured_one!(
         %{"tenant" => tenant, "id" => id, "type" => type, "token_hash" => hash, "capabilities" => caps} = value
       ) do
    if Map.keys(value) -- ~w(tenant id type token_hash capabilities) == [] and
         valid_id?(tenant) and valid_id?(id) and type in ["human", "agent", "service"] and
         is_binary(hash) and Regex.match?(~r/\A[0-9a-f]{64}\z/, hash) and is_list(caps) and
         Enum.all?(caps, &(&1 in @capabilities)) do
      %{tenant: tenant, id: id, type: type, token_hash: hash, capabilities: caps}
    else
      raise "PULSE_ALERTING_PRINCIPALS_JSON contains an invalid principal"
    end
  end

  defp parse_configured_one!(_), do: raise("PULSE_ALERTING_PRINCIPALS_JSON contains an invalid principal")

  @doc """
  Authenticates an alerting principal for `tenant`. A Tuist-issued credential
  maps its subject (with any delegating actor) and `alert:*` scopes onto the
  principal; otherwise the bearer must match a configured principal.
  """
  def authenticate(conn, tenant) do
    case Pulse.Auth.issuer_principal(conn) do
      :none -> authenticate_configured(conn, tenant)
      {:ok, %{tenant: ^tenant} = principal} -> {:ok, issuer_principal(principal)}
      _ -> {:error, :unauthorized}
    end
  end

  defp issuer_principal(principal) do
    %{
      tenant: principal.tenant,
      id: Issuer.actor_id(principal),
      type: principal.type,
      capabilities: Enum.filter(principal.scopes, &(&1 in @capabilities))
    }
  end

  defp authenticate_configured(conn, tenant) do
    with true <- valid_id?(tenant),
         [header] <- Plug.Conn.get_req_header(conn, "authorization"),
         true <- String.valid?(header),
         [scheme, token] when byte_size(token) > 0 <- String.split(header, " ", parts: 2),
         true <- String.downcase(scheme) == "bearer" do
      hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

      principal =
        Runtime.get_env(:pulse, Pulse.Alerting, [])
        |> Keyword.get(:principals, [])
        |> Enum.find(fn principal ->
          stored = Map.get(principal, :token_hash, "")

          Map.get(principal, :tenant) == tenant and is_binary(stored) and byte_size(stored) == 64 and
            Plug.Crypto.secure_compare(hash, stored)
        end)

      case principal do
        %{id: id, type: type, capabilities: caps} = value
        when is_binary(id) and type in ["human", "agent", "service"] and is_list(caps) ->
          {:ok, Map.take(value, [:tenant, :id, :type, :capabilities])}

        _ ->
          {:error, :unauthorized}
      end
    else
      _ -> {:error, :unauthorized}
    end
  end

  def authorize(principal, capability, classification \\ [])

  def authorize(%{tenant: tenant, id: id, type: type, capabilities: caps}, capability, classification)
      when is_binary(id) and type in ["human", "agent", "service"] and is_list(caps) do
    if valid_id?(tenant) and Enum.all?([capability | classification], &(&1 in @capabilities and &1 in caps)),
      do: :ok,
      else: {:error, :forbidden}
  end

  def authorize(_, _, _), do: {:error, :unauthorized}

  def valid_id?(value) when is_binary(value),
    do: byte_size(value) in 1..128 and value not in [".", ".."] and Regex.match?(~r/\A[A-Za-z0-9_.-]+\z/, value)

  def valid_id?(_), do: false
end
