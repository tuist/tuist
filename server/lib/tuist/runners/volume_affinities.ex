defmodule Tuist.Runners.VolumeAffinities do
  @moduledoc """
  Dispatch-time cache-volume affinity: prefer handing a polling runner a queued
  job whose cache volume's master is already resident on that node, so the job
  materializes warm instead of cold. A job's volume is its repository's; the
  account's `tuist-cache` master also counts for a repository volume, because
  the host seeds a repository with no master of its own from it.

  Affinity is a dispatch-scoring policy over the shared warm pool, plus a soft
  placement preference for new macOS Pods (see Custom volumes).
  `select_candidate/3` prefers a resident account's queued job, bounded by an
  age tolerance so affinity never delays a job past the tolerance (the precise
  operational meaning of the hard rule that affinity never starves an account
  holding no volume).

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

  ## Custom volumes

  Hosts on both platforms also advertise one `tuist.dev/cache-volume-<scope
  prefix>` label per custom volume lineage they hold a master of. A job attaches
  its custom volumes at runtime, so which ones a queued job will attach is
  predicted from history: the custom volumes that jobs with the same account,
  repository, workflow name and job name attached in the last week. A candidate
  counts as resident when the node holds any of them, under the same starvation
  bound. Residency still comes only from the host; history only predicts.

  A macOS Pod is placed before any job is assigned to it, so with one queued job
  and one new Pod there is nothing for dispatch to choose. The scaling signals
  therefore also carry, per queued job, a Node holding the volumes it is
  predicted to attach (`preferred_nodes/3`), and the runners controller prefers
  that Node for the Pod it creates for the job.

  ## Cache room

  A host admits a job's custom volumes only while its cache disk has room for
  what they are expected to write (`CacheVolumes` mirrors runner-cache's
  `Identity.ExpectedBytes`), and an attach it cannot admit runs cold. Affinity pulls an
  account's concurrent jobs toward the same host, so a preference that ignored
  room would stack jobs whose volumes cannot fit together. Every preference here
  therefore requires the job to fit: a host advertises its cache disk capacity
  (`tuist.dev/cache-volume-capacity-gib`), and its room is that capacity less
  the volumes of every job whose runner still occupies it (an open runner
  session), allocated or predicted. Counting predicted volumes matters because a
  job attaches minutes after dispatch, and a second job dispatched in between
  would see the host's own reservations still empty.

  A job that does not fit only loses the preference. Dispatch still hands out
  the oldest queued job, so cache room never delays one. A host that advertises
  no capacity is treated as having room.

  ## Why a node-pull dispatch is enough

  The server cannot place a job on a host of its choosing; it can only answer
  the host that asked. That is sufficient because the preference is
  self-reinforcing: a node that wins a volume's jobs keeps its master resident
  (materialize touches its mtime, so LRU keeps it), which keeps the node
  advertising it, which keeps the volume's jobs going there. The fleet settles into a
  stable partition of accounts over hosts without anything scheduling it.
  """
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.CacheVolumes
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.VolumeHeads

  require Logger

  @cache_master_label_prefix "tuist.dev/cache-master-"
  @repository_volumes_label "tuist.dev/cache-volumes-per-repository"
  @custom_volume_label_prefix "tuist.dev/cache-volume-"
  @custom_volume_label_scope_length 48
  @cache_capacity_label "tuist.dev/cache-volume-capacity-gib"
  @fleet_label "tuist.dev/fleet"

  # Which custom volumes a job attaches is only known from history, and a
  # workflow's volumes change on the order of commits, not polls.
  @custom_volume_history to_timeout(week: 1)
  @custom_volume_prediction_ttl to_timeout(minute: 1)

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

  defp no_cache_volumes,
    do: %{masters: MapSet.new(), custom: MapSet.new(), repository_volumes?: false, capacity_bytes: nil}

  @doc """
  The masters a Node's labels advertise as resident, as `{account_id, volume_name}`
  pairs, whether its tart-kubelet reads the Pod's cache volume label, and its
  cache disk capacity (`nil` when it advertises none).
  """
  def cache_volumes_from_node_labels(labels) when is_map(labels) do
    %{
      masters: masters_from_labels(labels),
      custom: custom_volumes_from_labels(labels),
      repository_volumes?: labels[@repository_volumes_label] == "true",
      capacity_bytes: capacity_from_labels(labels)
    }
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

  # The custom volume lineages the host holds a master of, as the scope prefix it
  # advertises.
  defp custom_volumes_from_labels(labels) do
    for {key, "true"} <- labels,
        String.starts_with?(key, @custom_volume_label_prefix),
        prefix = String.replace_prefix(key, @custom_volume_label_prefix, ""),
        Regex.match?(~r/\A[0-9a-f]{48}\z/, prefix),
        into: MapSet.new() do
      prefix
    end
  end

  defp capacity_from_labels(labels) do
    case Integer.parse(labels[@cache_capacity_label] || "") do
      {gib, ""} when gib >= 0 -> gib * 1024 * 1024 * 1024
      _ -> nil
    end
  end

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
  the oldest one whose volume's master is resident on the node and whose
  custom volumes fit in the node's cache room, UNLESS the queue head has
  itself been waiting longer than `:tolerance_seconds`, in which case the
  head is returned so it can't be passed over indefinitely.

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
    * `:no_room` — queued jobs belong to the node's masters, but the node's
      cache room cannot fit the volumes of any of them; the head goes out.
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
    node = node_cache_volumes(node_name)

    if MapSet.size(node.masters) == 0 and MapSet.size(node.custom) == 0 do
      {head, :no_residency}
    else
      case Enum.filter(candidates, &resident?(node, &1)) do
        [] ->
          {head, :no_resident_candidate}

        resident ->
          room = cache_room(node_name, node.capacity_bytes)

          case Enum.find(resident, &fits?(room, predicted_bytes(&1))) do
            nil -> {head, :no_room}
            # Checked before the starvation bound: an overdue head is handed out
            # either way, and reporting that as `:head_overdue` would hide that
            # the placement was warm anyway and make the bound look more
            # expensive than it is.
            ^head -> {head, :head_resident}
            candidate -> resolve_against_starvation_bound(candidate, head, tolerance_seconds)
          end
      end
    end
  end

  defp resident?(node, candidate) do
    builtin_resident?(node.masters, candidate) or custom_resident?(node.custom, candidate)
  end

  defp builtin_resident?(masters, %{account_id: account_id} = candidate) do
    volume_name = VolumeHeads.volume_name_for_repository(Map.get(candidate, :repository))

    MapSet.member?(masters, {account_id, volume_name}) or
      MapSet.member?(masters, {account_id, VolumeHeads.reserved_tuist_cache()})
  end

  # A candidate is resident when the node holds a lineage of any custom volume a
  # recent job of the same workflow and job attached.
  defp custom_resident?(custom, candidate) do
    MapSet.size(custom) > 0 and
      candidate |> predicted_label_scopes() |> Enum.any?(&MapSet.member?(custom, &1))
  end

  @doc """
  One Node per queued job in `candidates`, in candidate order and at most
  `limit`: a Node of `fleet_name` that holds a custom volume the job is
  predicted to attach and has cache room for all of them. Room a job is
  assigned is spent before the next job is placed, so a Node appears once per
  job it can fit. A job with no such Node gets no entry.

  The runners controller prefers the i-th Node for the i-th Pod it creates, so
  concurrent Pods are never steered onto a host whose cache disk cannot hold
  all of their volumes.
  """
  def preferred_nodes(fleet_name, candidates, limit) when is_list(candidates) and is_integer(limit) do
    case fleet_nodes(fleet_name) do
      [] ->
        []

      nodes ->
        committed = nodes |> Enum.filter(& &1.capacity_bytes) |> Enum.map(& &1.name) |> committed_bytes()
        rooms = Map.new(nodes, &{&1.name, room(&1.capacity_bytes, Map.get(committed, &1.name, 0))})

        candidates
        |> Enum.reduce_while({[], rooms}, fn candidate, {preferred, rooms} ->
          if length(preferred) == limit do
            {:halt, {preferred, rooms}}
          else
            {:cont, place(candidate, nodes, preferred, rooms)}
          end
        end)
        |> elem(0)
        |> Enum.reverse()
    end
  end

  # The holder of most of the job's volumes among those with room for all of
  # them, the one with the most known room on a tie.
  defp place(candidate, nodes, preferred, rooms) do
    scopes = MapSet.new(predicted_label_scopes(candidate))
    bytes = predicted_bytes(candidate)

    holders =
      for node <- nodes,
          held = node.custom |> MapSet.intersection(scopes) |> MapSet.size(),
          held > 0,
          fits?(rooms[node.name], bytes),
          do: {node.name, held}

    case Enum.max_by(holders, fn {name, held} -> {held, known_room(rooms[name])} end, fn -> nil end) do
      nil -> {preferred, rooms}
      {name, _held} -> {[name | preferred], Map.update!(rooms, name, &spend(&1, bytes))}
    end
  end

  defp fleet_nodes(fleet_name) do
    KeyValueStore.get_or_update(
      [:runner_fleet_cache_volumes, fleet_name],
      [ttl: @residency_cache_ttl],
      fn -> fetch_fleet_nodes(fleet_name) end
    )
  end

  defp fetch_fleet_nodes(fleet_name) do
    with {:ok, %{"spec" => %{"fleetSelector" => fleet}}} when is_binary(fleet) <-
           K8sClient.get_runner_pool(Environment.runners_namespace(), fleet_name),
         {:ok, %{"items" => items}} when is_list(items) <- K8sClient.list_nodes("#{@fleet_label}=#{fleet}") do
      for item <- items, name = get_in(item, ["metadata", "name"]), is_binary(name) do
        item |> get_in(["metadata", "labels"]) |> cache_volumes_from_node_labels() |> Map.put(:name, name)
      end
    else
      _ -> []
    end
  end

  # A host that advertises no capacity predates the label, and is treated as
  # having room so it keeps the preference it had before.
  defp cache_room(_node_name, nil), do: :unknown

  defp cache_room(node_name, capacity_bytes),
    do: room(capacity_bytes, [node_name] |> committed_bytes() |> Map.get(node_name, 0))

  defp room(nil, _committed), do: :unknown
  defp room(capacity_bytes, committed), do: capacity_bytes - committed

  defp fits?(:unknown, _bytes), do: true
  defp fits?(room, bytes), do: bytes <= room

  defp spend(:unknown, _bytes), do: :unknown
  defp spend(room, bytes), do: room - bytes

  defp known_room(:unknown), do: 0
  defp known_room(room), do: room

  # The cache disk room the jobs occupying `node_names` hold: each job's
  # allocated volumes plus those it is predicted to attach and has not yet.
  defp committed_bytes(node_names) do
    jobs = RunnerSessions.open_jobs_on_nodes(node_names)
    allocated = CacheVolumes.allocated_reserved_bytes(node_names, jobs |> Enum.map(& &1.workflow_job_id) |> Enum.uniq())

    Enum.reduce(jobs, %{}, fn job, committed ->
      bytes =
        job
        |> predicted_volumes()
        |> Map.new(&{&1.id, &1.reserved_bytes})
        |> Map.merge(Map.get(allocated, {job.node_name, job.workflow_job_id}, %{}))
        |> Map.values()
        |> Enum.sum()

      Map.update(committed, job.node_name, bytes, &(&1 + bytes))
    end)
  end

  defp predicted_bytes(candidate), do: candidate |> predicted_volumes() |> Enum.map(& &1.reserved_bytes) |> Enum.sum()

  defp predicted_label_scopes(candidate),
    do: candidate |> predicted_volumes() |> Enum.map(&String.slice(&1.scope, 0, @custom_volume_label_scope_length))

  defp predicted_volumes(%{account_id: account_id, repository: repository} = candidate)
       when is_integer(account_id) and is_binary(repository) do
    volumes =
      KeyValueStore.get_or_update(
        [:runner_custom_volume_predictions, account_id, repository],
        [ttl: @custom_volume_prediction_ttl],
        fn ->
          since = DateTime.add(DateTime.utc_now(), -@custom_volume_history, :millisecond)
          CacheVolumes.recent_job_volumes(account_id, repository, since)
        end
      )

    Map.get(volumes, {Map.get(candidate, :workflow_name), Map.get(candidate, :job_name)}, [])
  end

  defp predicted_volumes(_candidate), do: []

  # The head hit the starvation bound, so affinity must stop passing it over.
  # Reported apart from `:no_resident_candidate` so that `:head_overdue` counts
  # only the warm placements the bound actually gave up — the number the
  # tolerance should be tuned against.
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
