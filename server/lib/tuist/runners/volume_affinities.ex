defmodule Tuist.Runners.VolumeAffinities do
  @moduledoc """
  Dispatch-time cache-volume affinity: prefer handing a polling runner a queued
  job whose cache volume's master is already resident on that node, so the job
  materializes warm instead of cold. A job's volume is its repository's; the
  account's `tuist-cache` master also counts for a repository volume, because
  the host seeds a repository with no master of its own from it.

  Affinity is a pure dispatch-scoring policy over the shared warm pool — no
  Kubernetes scheduling change. `select_candidate/3` prefers a resident
  account's queued job, bounded by an age tolerance so affinity never delays a
  job past the tolerance (the precise operational meaning of the hard rule that
  affinity never starves an account holding no volume).

  ## Where residency comes from

  The host reports it. tart-kubelet scans the runner-cache root each node
  heartbeat and advertises one Node label per resident master
  (`VolumeManager.CacheMasterNodeLabels`): `tuist.dev/cache-master-<account_id>`
  for a `tuist-cache` master and `tuist.dev/cache-master-<account_id>.<volume>`
  for a repository's, the same mechanism it already uses to advertise its golden
  base VMs.

  This replaced a server-side model of residency built from dispatch history
  ("the N accounts that ran here most recently, where N is derived from the
  host's disk sizing"). That model was wrong in ways it could not detect:

    * An admission decline under disk pressure runs the job cold and creates no
      master, but the account still ran here most recently.
    * The background watermark evictor drops masters between jobs.
    * A reprovisioned host has nothing, and its dispatch history says otherwise.
    * N came from `gib/masterCapGib - (liveBranches + 1)`, a worst-case
      reservation formula, while admission actually compares free bytes against
      sparse images — so the survivor count was an assumption, not a fact.

  Reading the host's own scan makes all four moot.

  ## Why a node-pull dispatch is enough

  The server cannot place a job on a host of its choosing; it can only answer
  the host that asked. That is sufficient because the preference is
  self-reinforcing: a node that wins a volume's jobs keeps its master resident
  (materialize touches its mtime, so LRU keeps it), which keeps the node
  advertising it, which keeps the volume's jobs going there. The fleet settles into a
  stable partition of accounts over hosts without anything scheduling it.
  """
  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.VolumeHeads

  require Logger

  @cache_master_label_prefix "tuist.dev/cache-master-"
  @repository_volumes_label "tuist.dev/cache-volumes-per-repository"

  # A node advertises on a 30s heartbeat and masters change on the order of a
  # job, so a few seconds of staleness costs at most one cold materialize. This
  # keeps the apiserver read off the per-poll path: nine hosts polling every 2s
  # would otherwise be ~4.5 Node GETs/s, on the latency-sensitive dispatch path.
  @residency_cache_ttl to_timeout(second: 10)

  @doc """
  Set of `{account_id, volume_name}` masters `node_name` currently holds, read
  from the labels the host advertises.

  Returns an empty set when the node is unknown, unreadable, or advertises
  nothing — a host that reports no masters gets no preference and is handed
  plain oldest-queued work, which is also what every host does before the
  advertising build of tart-kubelet reaches it.
  """
  def resident_masters(node_name), do: node_cache_volumes(node_name).masters

  @doc """
  Whether `node_name`'s tart-kubelet reads the Pod's cache volume label. A job
  dispatched to a host that does not must stay on the account's `tuist-cache`
  volume, which is the only one that host materializes and promotes.
  """
  def repository_volumes?(node_name), do: node_cache_volumes(node_name).repository_volumes?

  defp node_cache_volumes(node_name) when is_binary(node_name) and node_name != "" do
    KeyValueStore.get_or_update(
      [:runner_node_cache_volumes, node_name],
      [ttl: @residency_cache_ttl],
      fn -> fetch_node_cache_volumes(node_name) end
    )
  end

  defp node_cache_volumes(_node_name), do: no_cache_volumes()

  defp fetch_node_cache_volumes(node_name) do
    case K8sClient.get_node(node_name) do
      {:ok, node} ->
        node |> get_in(["metadata", "labels"]) |> cache_volumes_from_node_labels()

      {:error, _reason} ->
        no_cache_volumes()
    end
  rescue
    # A Node read is an optimization input, not a correctness gate, and this
    # runs before the claim — so the cost of letting it escape is not a stranded
    # dispatch but a fleet-wide stall: every poll would 500 for as long as the
    # apiserver is unhappy. Degrade to no preference, which is just
    # oldest-queued. Mirrors how a failed `get_pod` already downgrades to `:ok`
    # and lets dispatch proceed.
    e ->
      Logger.warning("runners: cache residency lookup failed; dispatching without preference",
        node: node_name,
        reason: Exception.message(e)
      )

      no_cache_volumes()
  end

  defp no_cache_volumes, do: %{masters: MapSet.new(), repository_volumes?: false}

  @doc """
  The masters a Node's labels advertise as resident, as `{account_id, volume_name}`
  pairs, and whether its tart-kubelet reads the Pod's cache volume label.
  """
  def cache_volumes_from_node_labels(labels) when is_map(labels) do
    %{masters: masters_from_labels(labels), repository_volumes?: labels[@repository_volumes_label] == "true"}
  end

  def cache_volumes_from_node_labels(_labels), do: no_cache_volumes()

  defp masters_from_labels(labels) when is_map(labels) do
    for {key, "true"} <- labels,
        String.starts_with?(key, @cache_master_label_prefix),
        master <- [master_from_label(String.replace_prefix(key, @cache_master_label_prefix, ""))],
        master != nil,
        into: MapSet.new() do
      master
    end
  end

  defp masters_from_labels(_labels), do: MapSet.new()

  defp master_from_label(suffix) do
    case Integer.parse(suffix) do
      {account_id, ""} ->
        {account_id, VolumeHeads.reserved_tuist_cache()}

      {account_id, "." <> volume_name} ->
        if VolumeHeads.valid_volume_name?(volume_name), do: {account_id, volume_name}

      _ ->
        nil
    end
  end

  @doc """
  Picks the candidate a polling runner on `node_name` should be handed
  from a top-K list of queued candidates (ordered oldest-enqueued first):
  the oldest one whose volume's master is resident on the node, UNLESS the
  queue head has itself been waiting longer than `:tolerance_seconds`, in
  which case the head is returned so it can't be passed over indefinitely.

  The tolerance bounds how long the head can be delayed by affinity, measured
  from now — not the enqueue gap between the chosen candidate and the head.
  Comparing candidate-vs-head only bounds how far apart the two were enqueued,
  which a burst of affine jobs enqueued within the window can exploit to starve
  the head for far longer than the tolerance. Bounding head age from now caps
  the head's worst-case delay at `:tolerance_seconds`.

  Returns `nil` for an empty list, else `{candidate, outcome}`. The outcome is
  why that candidate was picked, so dispatch can report whether the preference
  is discriminating at all:

    * `:resident` — a queued job of a resident volume was preferred.
    * `:head_resident` — the head's own volume is resident; nothing was
      reordered but the job still lands warm.
    * `:no_resident_candidate` — the node holds masters, but none of the top-K
      queued jobs belong to them; the head goes out cold.
    * `:no_residency` — the node advertises no masters at all (a fresh or
      cache-off host, or one whose kubelet does not advertise yet).
    * `:head_overdue` — a resident candidate was queued, but the head hit the
      starvation bound and took precedence.

  ## Options

    * `:tolerance_seconds` — the starvation bound. Required.
  """
  def select_candidate(candidates, node_name, opts)

  def select_candidate([], _node_name, _opts), do: nil

  def select_candidate([head | _] = candidates, node_name, opts) do
    tolerance_seconds = Keyword.fetch!(opts, :tolerance_seconds)
    resident = resident_masters(node_name)

    cond do
      MapSet.size(resident) == 0 ->
        {head, :no_residency}

      # Checked before the starvation bound: an overdue head is handed out
      # either way, and reporting that as `:head_overdue` would hide that the
      # placement was warm anyway and make the bound look more expensive than
      # it is.
      resident?(resident, head) ->
        {head, :head_resident}

      true ->
        candidates
        |> Enum.find(&resident?(resident, &1))
        |> resolve_against_starvation_bound(head, tolerance_seconds)
    end
  end

  defp resident?(resident, %{account_id: account_id} = candidate) do
    volume_name = VolumeHeads.volume_name_for_repository(Map.get(candidate, :repository))

    MapSet.member?(resident, {account_id, volume_name}) or
      MapSet.member?(resident, {account_id, VolumeHeads.reserved_tuist_cache()})
  end

  # Nothing resident is queued, so the head goes out and the tolerance was never
  # in play. Reported apart from `:head_overdue` so that outcome counts only the
  # warm placements the bound actually gave up — the number the tolerance should
  # be tuned against.
  defp resolve_against_starvation_bound(nil, head, _tolerance_seconds), do: {head, :no_resident_candidate}

  defp resolve_against_starvation_bound(candidate, head, tolerance_seconds) do
    if head_overdue?(head, tolerance_seconds) do
      {head, :head_overdue}
    else
      {candidate, :resident}
    end
  end

  # The head is overdue once it has been queued longer than the tolerance,
  # measured from now. Past that point affinity must stop passing it over.
  defp head_overdue?(%{enqueued_at: %DateTime{} = head_enqueued_at}, tolerance_seconds) do
    DateTime.diff(DateTime.utc_now(), head_enqueued_at, :second) > tolerance_seconds
  end

  # Defensive: a head with no enqueue time can't be aged, so never treat it as
  # overdue — affinity may still prefer a resident candidate.
  defp head_overdue?(_head, _tolerance_seconds), do: false
end
