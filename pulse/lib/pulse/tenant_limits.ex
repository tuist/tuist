defmodule Pulse.TenantLimits do
  @moduledoc """
  Per-tenant admission limits from `PULSE_TENANT_LIMITS_JSON`, so one tenant
  cannot take a shared instance's capacity from the others:

      {"default": {"ingest_max_concurrent": 8},
       "tenants": {"acme": {"ingest_bytes_per_second": 10485760,
                            "query_max_concurrent": 4}}}

  Fields, all optional (a missing field is unlimited, or the node default):

    * `ingest_max_concurrent` - ingest requests one tenant may hold at once;
    * `ingest_bytes_per_second` and `ingest_burst_bytes` - a token bucket over
      request wire bytes (`Content-Length`; requests without one are charged
      1 MiB). The burst defaults to twice the rate and at least 4 MiB, so one
      maximum-size request always fits;
    * `query_max_concurrent` - interactive queries one tenant may run at once
      (default 2).

  Limits apply per instance, like every other admission bound: with N
  instances behind a balancer a tenant can use up to N times the rate. Buckets
  are disposable node-local state; refills race benignly, so a burst can be
  slightly exceeded under contention but never by more than one request per
  concurrent caller.
  """

  @fields Map.new(
            ~w(ingest_max_concurrent ingest_bytes_per_second ingest_burst_bytes query_max_concurrent)a,
            &{Atom.to_string(&1), &1}
          )
  @min_burst 4 * 1_048_576
  @table __MODULE__.Buckets

  @type limits :: %{optional(atom()) => pos_integer()}

  @doc "Parse the JSON document; raises with a readable message when invalid."
  @spec parse!(String.t()) :: %{default: limits(), tenants: %{String.t() => limits()}}
  def parse!(json) do
    case JSON.decode(json) do
      {:ok, %{} = doc} ->
        if Map.keys(doc) -- ["default", "tenants"] != [], do: invalid!("unknown top-level key")
        tenants = Map.get(doc, "tenants", %{})
        if !is_map(tenants), do: invalid!("tenants must be an object")

        %{
          default: limits!(Map.get(doc, "default", %{}), "default"),
          tenants: Map.new(tenants, fn {tenant, limits} -> {tenant, limits!(limits, tenant)} end)
        }

      _ ->
        invalid!("not a JSON object")
    end
  end

  defp limits!(%{} = map, owner) do
    Map.new(map, fn
      {field, value} when is_map_key(@fields, field) and is_integer(value) and value in 1..1_099_511_627_776 ->
        {Map.fetch!(@fields, field), value}

      {field, _} ->
        invalid!("#{owner}.#{field} must be a known field with a positive integer")
    end)
  end

  defp limits!(_, owner), do: invalid!("#{owner} must be an object")

  defp invalid!(reason), do: raise("PULSE_TENANT_LIMITS_JSON is invalid: #{reason}")

  @doc "Whether any tenant limit is configured on this node."
  def configured?, do: config() != %{default: %{}, tenants: %{}}

  @doc "One limit for `tenant`, falling back to the default entry, or nil."
  @spec get(String.t(), atom()) :: pos_integer() | nil
  def get(tenant, field) do
    %{default: default, tenants: tenants} = config()
    tenants |> Map.get(tenant, %{}) |> Map.get(field, Map.get(default, field))
  end

  defp config, do: Keyword.get(Pulse.Runtime.get_env(:pulse, __MODULE__, []), :limits, %{default: %{}, tenants: %{}})

  @doc """
  Take `bytes` from `tenant`'s ingest bucket, or `{:error, :tenant_rate}` when
  it is empty. Unlimited tenants always pass.
  """
  @spec take_ingest_bytes(String.t(), non_neg_integer() | nil) :: :ok | {:error, :tenant_rate}
  def take_ingest_bytes(tenant, bytes) do
    case get(tenant, :ingest_bytes_per_second) do
      nil -> :ok
      rate -> take(tenant, bytes || 1_048_576, rate, get(tenant, :ingest_burst_bytes) || max(2 * rate, @min_burst))
    end
  end

  defp take(tenant, bytes, rate, burst) do
    table = Pulse.Runtime.table(@table)
    now = System.monotonic_time(:millisecond)

    {tokens, at} =
      case :ets.lookup(table, tenant) do
        [{_, tokens, at}] -> {tokens, at}
        [] -> {burst, now}
      end

    available = min(burst, tokens + div((now - at) * rate, 1000))

    if available >= bytes do
      :ets.insert(table, {tenant, available - bytes, now})
      :ok
    else
      :ets.insert(table, {tenant, available, now})
      {:error, :tenant_rate}
    end
  rescue
    # The table belongs to Pulse.IngestAdmission; without it, never fail ingest.
    ArgumentError -> :ok
  end

  @doc false
  def table, do: @table
end
