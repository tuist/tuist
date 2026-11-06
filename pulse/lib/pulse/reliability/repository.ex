defmodule Pulse.Reliability.Repository do
  @moduledoc false
  alias Pulse.Alerting.Canonical
  alias Pulse.ObjectStore
  alias Pulse.Runtime
  alias Pulse.Storage.S3

  @root_bytes 2_097_152

  def config, do: Map.new(Runtime.get_env(:pulse, S3, []))
  def key(tenant), do: "tenants/#{tenant}/reliability/v1/head.json"
  def nonce, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

  def now(config), do: Keyword.get(config, :clock_ns, fn -> System.system_time(:nanosecond) end).()

  def authorize(config, earliest \\ 0) do
    now = now(config)
    date = now |> div(1_000_000_000) |> DateTime.from_unix!() |> DateTime.to_date() |> Date.to_iso8601()

    cond do
      now < earliest ->
        {:error, :reliability_clock_regressed}

      not is_binary(config[:price_valid_until]) or config[:price_valid_until] < date ->
        {:error, :reliability_price_expired}

      true ->
        {:ok, now}
    end
  end

  def load(tenant) do
    with :ok <- S3.validate_tenant(tenant) do
      case ObjectStore.get_bounded(config(), key(tenant), nil, @root_bytes) do
        {:ok, etag, bytes} ->
          decode(bytes, etag)

        {:error, :not_found} ->
          {:ok, empty(), nil}

        error ->
          error
      end
    end
  end

  defp decode(bytes, etag) do
    case Pulse.JSON.decode(bytes) do
      {:ok, %{"version" => 1} = root} -> {:ok, root, etag}
      _ -> {:error, :invalid_reliability_state}
    end
  end

  def transact(tenant, fun), do: transact(tenant, fun, 4)
  defp transact(_tenant, _fun, 0), do: {:error, :reliability_conflict}

  defp transact(tenant, fun, attempts) do
    with {:ok, root, etag} <- load(tenant),
         {:ok, next, result} <- fun.(root),
         next = Map.put(next, "publication", nonce()),
         bytes = Canonical.encode(next),
         true <- byte_size(bytes) <= @root_bytes do
      case put(tenant, bytes, etag) do
        {:ok, _} ->
          {:ok, result}

        {:error, reason} when reason in [:precondition_failed, :already_exists] ->
          transact(tenant, fun, attempts - 1)

        _ ->
          # A failed response can follow a successful CAS. Never independently
          # acknowledge a result unless the exact candidate was committed.
          readback(tenant, bytes, result)
      end
    else
      false -> {:error, :reliability_state_limit}
      error -> error
    end
  end

  defp readback(tenant, bytes, result) do
    case ObjectStore.get_bounded(config(), key(tenant), nil, @root_bytes) do
      {:ok, _, ^bytes} -> {:ok, result}
      _ -> {:error, :reliability_publication_unknown}
    end
  end

  def event(root, kind, data) do
    sequence = root["sequence"] + 1

    change =
      Map.merge(data, %{"kind" => kind, "sequence" => sequence, "change_id" => "#{root["generation"]}:#{sequence}"})

    changes = Enum.take(root["changes"] ++ [change], -128)
    Map.merge(root, %{"sequence" => sequence, "changes" => changes, "replay_floor" => hd(changes)["sequence"] - 1})
  end

  def charge(root, now, kind, amount, limit) do
    month = now |> div(1_000_000_000) |> DateTime.from_unix!() |> Calendar.strftime("%Y-%m")
    spent = Map.get(root["spend"], month, %{})
    used = Map.get(spent, kind, 0)

    if used + amount <= limit do
      spend =
        root["spend"]
        |> Map.put(month, Map.put(spent, kind, used + amount))
        |> Enum.sort(:desc)
        |> Enum.take(2)
        |> Map.new()

      {:ok, Map.put(root, "spend", spend)}
    else
      {:error, :reliability_budget_exhausted}
    end
  end

  defp put(tenant, bytes, nil), do: ObjectStore.put_if_none_match(config(), key(tenant), bytes)
  defp put(tenant, bytes, etag), do: ObjectStore.put_if_match(config(), key(tenant), bytes, etag)

  defp empty do
    %{
      "version" => 1,
      "generation" => nonce(),
      "sequence" => 0,
      "replay_floor" => 0,
      "changes" => [],
      "signals" => %{},
      "assessments" => %{},
      "spend" => %{},
      "investigations" => %{},
      "clock_ns" => 0
    }
  end
end
