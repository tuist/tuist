defmodule Pulse.Storage.S3.MetricMetadataStore do
  @moduledoc """
  The per-tenant metric metadata object, `tenants/<tenant>/v4/metadata/metrics.json`
  (see `Pulse.MetricMetadata`). Writers merge with conditional PUTs and retry
  on conflicts, so concurrent instances never lose each other's variants;
  unchanged sets cost one GET and no write. Reads always GET the object, so
  every instance serves the latest published set.

  Remote write 2.0 senders attach metadata to every request, so each instance
  also remembers which entries it has seen published for the day, in a
  disposable, bounded node-local table. A request whose entries are all known
  skips the GET and decode of the whole set. Other instances only add variants
  or refresh days, so a remembered entry stays published for that day; the
  merge bounds can still evict it, which at worst delays its next report until
  the following day or until the table is cleared.
  """

  use Pulse.Runtime.GenServer

  alias Pulse.MetricMetadata
  alias Pulse.ObjectStore
  alias Pulse.Runtime.GenServer

  @attempts 16
  @table __MODULE__
  # 16-byte keys and a day: a few MiB at most. Overflow clears the table.
  @max_published 100_000

  def key(tenant), do: "tenants/#{tenant}/v4/metadata/metrics.json"

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(table(), [:named_table, :public, :set, read_concurrency: true, write_concurrency: true])
    {:ok, nil}
  end

  defp table, do: Pulse.Runtime.table(@table)

  @spec put(map(), String.t(), [MetricMetadata.entry()], integer()) :: :ok | {:error, term()}
  def put(config, tenant, entries, today) do
    fingerprints = Enum.map(entries, &fingerprint(config, tenant, &1))

    if Enum.all?(fingerprints, &published?(&1, today)),
      do: :ok,
      else: put(config, tenant, entries, today, @attempts)
  end

  defp put(_config, _tenant, _entries, _today, 0), do: {:error, :metric_metadata_conflict}

  defp put(config, tenant, entries, today, attempts) do
    with {:ok, etag, set} <- load(config, tenant) do
      if MetricMetadata.changed?(set, entries, today),
        do: write(config, tenant, etag, MetricMetadata.merge(set, entries, today), {entries, today, attempts}),
        else: remember(config, tenant, set, entries, today)
    end
  end

  # The store's identity is part of the fingerprint, so instances of different
  # buckets or endpoints never share facts.
  defp fingerprint(config, tenant, entry) do
    identity = {Map.get(config, :endpoint), Map.get(config, :bucket), tenant, entry}
    binary_part(:crypto.hash(:sha256, :erlang.term_to_binary(identity)), 0, 16)
  end

  defp published?(fingerprint, today) do
    match?([{_, ^today}], :ets.lookup(table(), fingerprint))
  rescue
    ArgumentError -> false
  end

  # Remember only entries the set proves published today; bounds may have
  # dropped others from a merged set.
  defp remember(config, tenant, set, entries, today) do
    published = for entry <- entries, not MetricMetadata.changed?(set, [entry], today), do: entry

    case :ets.info(table(), :size) do
      :undefined ->
        :ok

      size ->
        if size + length(published) > @max_published, do: :ets.delete_all_objects(table())
        :ets.insert(table(), Enum.map(published, &{fingerprint(config, tenant, &1), today}))
        :ok
    end
  rescue
    # The table can disappear while its owner restarts.
    ArgumentError -> :ok
  end

  defp write(config, tenant, etag, merged, {entries, today, attempts}) do
    body = MetricMetadata.encode(merged)

    result =
      if etag,
        do: ObjectStore.put_if_match(config, key(tenant), body, etag),
        else: ObjectStore.put_if_none_match(config, key(tenant), body)

    case result do
      {:ok, _etag} ->
        remember(config, tenant, merged, entries, today)

      {:error, reason} when reason in [:precondition_failed, :already_exists, :not_found] ->
        backoff(attempts)
        put(config, tenant, entries, today, attempts - 1)

      {:error, _} = error ->
        error
    end
  end

  # Jittered, growing waits so concurrent writers stop colliding.
  defp backoff(attempts) do
    round = @attempts - attempts + 1
    Process.sleep(:rand.uniform(20 * round))
  end

  @spec get(map(), String.t()) :: {:ok, MetricMetadata.set()} | {:error, term()}
  def get(config, tenant) do
    with {:ok, _etag, set} <- load(config, tenant), do: {:ok, set}
  end

  defp load(config, tenant) do
    case ObjectStore.get_bounded(config, key(tenant), nil, MetricMetadata.max_bytes()) do
      {:ok, etag, body} ->
        with {:ok, set} <- MetricMetadata.decode(body), do: {:ok, etag, set}

      {:error, :not_found} ->
        {:ok, nil, %{}}

      {:error, _} = error ->
        error
    end
  end
end
