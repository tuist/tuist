defmodule Symptoms.Lifecycle do
  @moduledoc """
  One window's detection after the evidence is combined: roots, the CUSUM
  per root, opening, merging and resolving symptoms, the tier decision and
  the revisions it writes (README "Combining", "Decision" and "Symptom
  log").

  - **Degraded**: an entity whose combined log-evidence exceeds
    `degraded_nats` this window; its run in this pipeline starts at its
    `Symptoms.Store.DegradedRun` (one per entity and `window_seconds`).
  - **Roots**: `Symptoms.Evidence.Roots.analyze/3` over the degraded entities
    and the stored edges. A degraded entity's root key is its root's; any
    other entity is its own root. Keys are prefixed with the window length
    (`"60:entity:42"`, `"300:shared:entity:7"`), so the 1- and 5-minute
    pipelines keep separate detectors and symptoms.
  - **CUSUM**: per root key, `S = max(0, S + x - drift)` where `x` is the
    largest combined log-evidence among the root's unexplained members
    (callers explained by a callee add only impact). A new root key starts
    from the largest CUSUM its members had on their own keys, and a symptom
    that moves to a new root brings its CUSUM along, so regrouping never
    loses evidence. State older than 5 windows is stale and restarts.
  - **Open**: when a root's CUSUM reaches `h`, every member entity without
    an open symptom gets one: the resolved symptom with the same
    `symptom_key` within `reopen_hours` reopens, otherwise a new one opens.
  - **Merge**: an open symptom that was its own root and now sits under
    another root symptom becomes `merged` into it.
  - **Resolve**: after `resolve_after_quiet_windows` consecutive quiet
    windows (no member of the root degraded and the root's log-evidence not
    positive; a non-positive window where any member is unknown neither
    counts nor resets) all its symptoms resolve and its CUSUM restarts at 0.
  - **Decision**: P(degraded) is Platt on the root's CUSUM; impact is the
    entity's rate. `Symptoms.Decision.Policy.decide/3` runs over every open
    and merged symptom with the roots already charged, so a root pays for
    one page. A muted entity and phenomenon goes to audit; a mute matches the
    full entity key or its trimmed form (`Symptoms.Log.trim_key/1`). Pages
    are delivered by `Symptoms.Paging` once any recorded delay has passed,
    only if the root is still at page tier and not muted, after the window's
    transaction commits. The published delay is the one stored on the
    symptom (charged page or board push), never a per-window draw.
  - **Fresh rows**: the open symptoms are locked and read again inside the
    window's transaction, so fields the board push or the state read-back
    committed meanwhile are not overwritten.
  - **Revisions**: on a material change (opened, reopened, resolved,
    merged, tier, root, impact 2× or more, outcome or brief), otherwise at
    most one coalesced `annotated` revision per `coalesce_minutes` when the
    snapshot changed.
  """

  import Ecto.Query

  alias Symptoms.Decision.Platt
  alias Symptoms.Decision.Policy
  alias Symptoms.Deploys
  alias Symptoms.Evidence.Combine
  alias Symptoms.Evidence.Roots
  alias Symptoms.Log
  alias Symptoms.Paging
  alias Symptoms.Repo
  alias Symptoms.Settings
  alias Symptoms.Store
  alias Symptoms.Store.DegradedRun
  alias Symptoms.Store.DetectorState
  alias Symptoms.Store.Entity
  alias Symptoms.Store.HumanMute
  alias Symptoms.Store.RootScore
  alias Symptoms.Store.Symptom

  @tier_rank %{"audit" => 0, "board" => 1, "page" => 2}
  @stale_windows 5
  @detector_fields [:cusum, :window_seconds, :last_window_start, :quiet_windows, :symptom_id, :updated_at]
  @volatile ~w(seq revision transition updated_at schema_version symptom_id)

  @type entity_score :: %{
          x: float(),
          phenomena: [map()],
          impact_unit: String.t() | nil,
          impact_rate: float() | nil,
          examples: [String.t()]
        }

  @doc """
  Runs detection for one window. `scores` maps entity ids to their combined
  score (`t:entity_score/0`); `now` is the decision time. Returns
  `%{opened, reopened, resolved, charged_roots, revisions, open_symptoms}`,
  where `open_symptoms` maps each entity with an unresolved symptom to it.
  """
  @spec step(pos_integer(), DateTime.t(), %{optional(integer()) => entity_score()}, DateTime.t(), keyword()) :: map()
  def step(window_seconds, window_start, scores, now, opts \\ []) do
    prefix = "#{window_seconds}:"
    config = config(window_seconds)

    degraded =
      for {id, score} <- scores, score.x > config.degraded_nats, into: MapSet.new(), do: id

    since = update_degraded_runs(window_seconds, Map.keys(scores), degraded, window_start)

    analysis =
      Roots.analyze(
        Enum.map(degraded, &%{entity: &1, direction: :up, start: since[&1]}),
        Store.edges(),
        window_seconds: window_seconds
      )

    root_of =
      Map.new(scores, fn {id, _} ->
        root = if MapSet.member?(degraded, id), do: analysis.root_of[id], else: id
        {id, prefix <> encode(root)}
      end)

    roots = group_roots(root_of, scores, analysis, prefix)

    open =
      Repo.all(from(s in Symptom, where: s.state in ["open", "merged"] and like(s.root_key, ^"#{prefix}%")))

    states = load_states(roots, open, prefix, window_start, window_seconds)
    unknown = unknown_entities(open, roots)
    stepped = step_detectors(roots, open, states, degraded, unknown, config.drift)

    {:ok, {result, work}} =
      Repo.transaction(fn ->
        open = relock(open)
        {open, stepped} = reassign(open, root_of, degraded, stepped)
        {resolving, stepped} = resolving(open, stepped, config.resolve_after)

        work = Map.new(open, &{&1.id, %{sym: &1, hint: if(&1.root_key in resolving, do: :resolve)}})
        work = open_crossings(work, roots, stepped, scores, config, now)
        work = assign_roots(work, roots)
        work = decide(work, stepped, scores, window_seconds, now)
        {work, revisions} = write(work, stepped, scores, now)
        persist_detectors(stepped, work, window_seconds, window_start, now)
        persist_root_scores(stepped, roots, work, window_seconds, window_start)

        result = summarize(work, revisions)
        if complete = opts[:complete], do: complete.(result)
        {result, work}
      end)

    # Only committed revisions page.
    page(work, now)
    result
  end

  # The open symptoms again, locked, inside the window's transaction: the
  # board push (`delayed_until`, `delay_probability`, `board`) and the state
  # read-back (`outcome`) may have committed since they were read, and the
  # window's writes must carry those fields, not the stale ones. The log lock
  # comes first, even with nothing open, the order every revision writer
  # locks in.
  defp relock(open) do
    Log.lock!()
    ids = Enum.map(open, & &1.id)

    fresh =
      Map.new(
        Repo.all(from(s in Symptom, where: s.id in ^ids and s.state in ["open", "merged"], lock: "FOR UPDATE")),
        &{&1.id, &1}
      )

    for sym <- open, current = fresh[sym.id], current != nil, do: current
  end

  defp config(window_seconds) do
    %{
      h: Settings.h(window_seconds),
      drift: Settings.detector(:drift) * 1.0,
      degraded_nats: Settings.detector(:degraded_nats),
      resolve_after: Settings.detector(:resolve_after_quiet_windows),
      reopen_hours: Settings.detector(:reopen_hours)
    }
  end

  ## Roots

  @doc "Encodes a `Symptoms.Evidence.Roots` root key as a string."
  @spec encode(term()) :: String.t()
  def encode(id) when is_integer(id), do: "entity:#{id}"
  def encode({:cycle, members}), do: "cycle:" <> Enum.map_join(members, ",", &to_string/1)
  def encode({:shared_cause, members}) when is_list(members), do: "shared:" <> Enum.map_join(members, "+", &encode/1)
  def encode({:shared_cause, resource}), do: "shared:" <> encode(resource)

  defp update_degraded_runs(window_seconds, ids, degraded, window_start) do
    degraded_ids = MapSet.to_list(degraded)
    quiet_ids = ids -- degraded_ids

    Repo.delete_all(from(d in DegradedRun, where: d.window_seconds == ^window_seconds and d.entity_id in ^quiet_ids))

    Repo.insert_all(
      DegradedRun,
      Enum.map(degraded_ids, &%{entity_id: &1, window_seconds: window_seconds, since: window_start}),
      on_conflict: :nothing,
      conflict_target: [:entity_id, :window_seconds]
    )

    Map.new(
      Repo.all(
        from(d in DegradedRun,
          where: d.window_seconds == ^window_seconds and d.entity_id in ^degraded_ids,
          select: {d.entity_id, d.since}
        )
      )
    )
  end

  defp group_roots(root_of, scores, analysis, prefix) do
    root_of
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    |> Map.new(fn {key, members} ->
      explained = Enum.filter(members, &Map.has_key?(analysis.explained_by, Map.get(analysis.components, &1)))
      leaders = if explained == members, do: members, else: members -- explained
      lead = Enum.max_by(Enum.sort(leaders), &scores[&1].x)
      rates = Enum.map(members, &scores[&1].impact_rate)

      {key,
       %{
         members: Enum.sort(members),
         lead: lead,
         x: scores[lead].x,
         shared: String.starts_with?(key, prefix <> "shared:"),
         impact: if(Enum.any?(rates, &is_nil/1), do: nil, else: Enum.sum(rates))
       }}
    end)
  end

  ## Detectors

  defp load_states(roots, open, prefix, window_start, window_seconds) do
    own = roots |> Map.values() |> Enum.flat_map(& &1.members) |> Enum.map(&"#{prefix}entity:#{&1}")
    keys = Enum.uniq(Map.keys(roots) ++ Enum.map(open, & &1.root_key) ++ own)
    fresh_after = DateTime.shift(window_start, second: -@stale_windows * window_seconds)

    from(d in DetectorState, where: d.root_key in ^keys and d.last_window_start >= ^fresh_after)
    |> Repo.all()
    |> Map.new(&{&1.root_key, &1})
  end

  defp unknown_entities(open, roots) do
    ids = Enum.uniq(Enum.map(open, & &1.entity_id) ++ Enum.flat_map(Map.values(roots), & &1.members))
    MapSet.new(Repo.all(from(e in Entity, where: e.id in ^ids and e.unknown, select: e.id)))
  end

  defp step_detectors(roots, open, states, degraded, unknown, drift) do
    open_entities = Enum.group_by(open, & &1.root_key, & &1.entity_id)
    keys = Enum.uniq(Map.keys(roots) ++ Map.keys(open_entities))

    Map.new(keys, fn key ->
      root = roots[key]
      previous = states[key]
      prev_s = if previous, do: previous.cusum, else: carry(root, states, key)
      prev_q = if previous, do: previous.quiet_windows, else: 0

      {x, quiet} = observe(root, open_entities[key], degraded, unknown)
      {key, %{cusum: Combine.cusum_step(prev_s, x, drift), previous: prev_s, quiet: quiet_count(quiet, prev_q), x: x}}
    end)
  end

  # `{x, quiet?}` for one root this window; `quiet?` is nil when an
  # open root has a member with missing evidence. Recovery requires all
  # members to be observable; positive evidence can still increase its score.
  defp observe(nil, entity_ids, _degraded, unknown) do
    if Enum.any?(entity_ids, &MapSet.member?(unknown, &1)), do: {0.0, nil}, else: {0.0, true}
  end

  defp observe(root, entity_ids, degraded, unknown) do
    members = Enum.uniq(root.members ++ (entity_ids || []))

    if root.x <= 0 and Enum.any?(members, &MapSet.member?(unknown, &1)),
      do: {0.0, nil},
      else: {root.x, root.x <= 0 and not Enum.any?(members, &MapSet.member?(degraded, &1))}
  end

  defp quiet_count(true, previous), do: previous + 1
  defp quiet_count(false, _previous), do: 0
  defp quiet_count(nil, previous), do: previous

  defp carry(nil, _states, _key), do: 0.0

  defp carry(root, states, key) do
    prefix = key |> String.split(":", parts: 2) |> hd()

    root.members
    |> Enum.map(&"#{prefix}:entity:#{&1}")
    |> Enum.reject(&(&1 == key))
    |> Enum.map(&((states[&1] && states[&1].cusum) || 0.0))
    |> Enum.max(fn -> 0.0 end)
  end

  # An open symptom on a degraded entity follows the entity's current root,
  # and the new root takes the larger CUSUM.
  defp reassign(open, root_of, degraded, stepped) do
    Enum.map_reduce(open, stepped, fn sym, stepped ->
      new_key = root_of[sym.entity_id]

      if MapSet.member?(degraded, sym.entity_id) and new_key != sym.root_key do
        old = stepped[sym.root_key]
        stepped = Map.update!(stepped, new_key, &%{&1 | cusum: max(&1.cusum, old.cusum)})
        {%{sym | root_key: new_key}, stepped}
      else
        {sym, stepped}
      end
    end)
  end

  defp resolving(open, stepped, resolve_after) do
    keys = for s <- open, stepped[s.root_key].quiet >= resolve_after, uniq: true, do: s.root_key
    stepped = Enum.reduce(keys, stepped, &Map.update!(&2, &1, fn s -> %{s | cusum: 0.0, quiet: 0} end))
    {keys, stepped}
  end

  ## Opening

  defp open_crossings(work, roots, stepped, scores, config, now) do
    with_symptom = work |> Map.values() |> Enum.reject(&(&1.hint == :resolve)) |> MapSet.new(& &1.sym.entity_id)

    roots
    |> Enum.filter(fn {key, _} -> stepped[key].cusum >= config.h end)
    |> Enum.sort()
    |> Enum.reduce(work, fn {key, root}, work ->
      phenomenon = dominant(scores[root.lead].phenomena)

      root.members
      |> Enum.reject(&MapSet.member?(with_symptom, &1))
      |> Enum.reduce(work, fn entity_id, work ->
        {sym, hint} = open_symptom(entity_id, key, phenomenon, config.reopen_hours, now)
        Map.put(work, sym.id, %{sym: sym, hint: hint})
      end)
    end)
  end

  defp dominant([]), do: "request_errors"

  defp dominant(phenomena) do
    phenomena |> Enum.max_by(&{&1.nats, to_string(&1.phenomenon)}) |> Map.fetch!(:phenomenon) |> to_string()
  end

  defp open_symptom(entity_id, key, phenomenon, reopen_hours, now) do
    entity = Repo.get!(Entity, entity_id)
    symptom_key = Log.symptom_key({entity.environment, entity.service, entity.kind, entity.key}, phenomenon)
    reopen_after = DateTime.shift(now, hour: -reopen_hours)
    pipeline = hd(String.split(key, ":", parts: 2)) <> ":%"

    reopenable =
      Repo.one(
        from(s in Symptom,
          where: s.symptom_key == ^symptom_key and s.state == "resolved" and s.resolved_at >= ^reopen_after,
          where: like(s.root_key, ^pipeline),
          order_by: [desc: s.resolved_at],
          limit: 1
        )
      )

    case reopenable do
      nil ->
        {%Symptom{
           id: Log.uuid7(now),
           symptom_key: symptom_key,
           root_key: key,
           entity_id: entity_id,
           phenomenon: phenomenon,
           state: "open",
           tier: "audit",
           max_tier: "audit",
           opened_at: now,
           inserted_at: now,
           updated_at: now
         }, :opened}

      sym ->
        {%{
           sym
           | state: "open",
             root_key: key,
             resolved_at: nil,
             merged_into: nil,
             charged: false,
             paged_at: nil,
             page_logged_at: nil,
             delayed_until: nil
         }, :reopened}
    end
  end

  ## Roots of symptoms

  defp assign_roots(work, roots) do
    work
    |> Map.values()
    |> Enum.reject(&(&1.hint == :resolve))
    |> Enum.group_by(& &1.sym.root_key)
    |> Enum.reduce(work, fn {key, items}, work ->
      root_item = root_item(items, roots[key])
      member_ids = items |> Enum.map(& &1.sym.id) |> Enum.reject(&(&1 == root_item.sym.id)) |> Enum.sort()
      shared = String.contains?(key, ":shared:")

      Enum.reduce(items, work, fn item, work ->
        is_root = item.sym.id == root_item.sym.id
        sym = place(item, is_root, root_item.sym.id)

        root = %{
          "root_symptom_id" => root_item.sym.id,
          "member_symptom_ids" => if(is_root, do: member_ids, else: []),
          "shared_cause" => shared
        }

        Map.put(work, sym.id, Map.merge(item, %{sym: sym, root: root}))
      end)
    end)
  end

  # The root opens; a symptom that was its own root and now sits under
  # another merges into it; merged symptoms follow the current root.
  defp place(%{sym: sym}, true, _root_id), do: %{sym | state: "open", merged_into: nil}
  defp place(%{sym: %{state: "merged"} = sym}, false, root_id), do: %{sym | merged_into: root_id}

  defp place(%{sym: %{state: "open"} = sym, hint: nil}, false, root_id) do
    if own_root?(sym), do: %{sym | state: "merged", merged_into: root_id}, else: sym
  end

  defp place(%{sym: sym}, false, _root_id), do: sym

  defp own_root?(sym), do: sym.revision > 0 and get_in(sym.document || %{}, ["root", "root_symptom_id"]) in [nil, sym.id]

  defp root_item(items, root) do
    lead = root && Enum.find(items, &(&1.sym.entity_id == root.lead and &1.sym.state == "open"))
    open = Enum.filter(items, &(&1.sym.state == "open"))
    candidates = if open == [], do: items, else: open

    lead || Enum.min_by(candidates, &{DateTime.to_unix(&1.sym.opened_at, :microsecond), &1.sym.id})
  end

  ## Decision

  defp decide(work, stepped, scores, window_seconds, now) do
    params = Settings.platt(window_seconds)
    opts = Settings.policy_opts()
    active = work |> Map.values() |> Enum.reject(&(&1.hint == :resolve))
    muted = muted_ids(active, now)

    inputs =
      Enum.map(active, fn %{sym: sym} ->
        score = stepped[sym.root_key].cusum
        impact = if(s = scores[sym.entity_id], do: s.impact_rate, else: sym.impact_rate)
        %{id: sym.id, root: sym.root_key, p: Platt.probability(params, score), impact: impact, score: score}
      end)

    charged = for %{sym: %{charged: true, root_key: key}} <- active, uniq: true, do: key
    {decidable, muted_inputs} = Enum.split_with(inputs, &(not MapSet.member?(muted, &1.id)))
    result = Policy.decide(decidable, now, Keyword.put(opts, :charged_roots, charged))
    new_charges = MapSet.new(result.charged_roots)
    minutes = Policy.minutes_until_review(now)
    price = if Policy.night?(now), do: opts[:night_price], else: opts[:day_price]

    muted_decisions =
      Map.new(muted_inputs, fn input ->
        {input.id,
         %{
           tier: :audit,
           would_page: false,
           root: input.root,
           expected_cost: if(is_number(input.impact), do: input.p * input.impact * minutes),
           price: price,
           delayed_until: nil,
           delay_probability: 0.0
         }}
      end)

    decisions = Map.merge(result.decisions, muted_decisions)
    Enum.each(result.charged_roots, &Store.audit("page_charged", now, data: %{root_key: &1}))

    Enum.reduce(inputs, work, fn input, work ->
      decision = decisions[input.id]

      Map.update!(work, input.id, fn item ->
        item
        |> apply_decision(input, decision, new_charges, scores)
        |> Map.put(:muted, MapSet.member?(muted, input.id))
      end)
    end)
  end

  defp apply_decision(item, input, decision, new_charges, scores) do
    sym = charge(item.sym, decision, MapSet.member?(new_charges, item.sym.root_key))
    tier = Atom.to_string(decision.tier)

    sym = %{
      sym
      | tier: tier,
        max_tier: max_tier(sym.max_tier, tier),
        score: input.score,
        max_score: max(sym.max_score || 0.0, input.score),
        p_degraded: input.p,
        expected_cost: decision.expected_cost,
        impact_rate: optional(input.impact, &(&1 * 1.0)),
        impact_unit: impact_unit(scores[sym.entity_id], sym)
    }

    Map.merge(item, %{sym: sym, decision: decision})
  end

  defp charge(sym, decision, true),
    do: %{sym | charged: true, delayed_until: decision.delayed_until, delay_probability: decision.delay_probability}

  defp charge(sym, _decision, false), do: sym

  defp max_tier(a, b), do: if(@tier_rank[b] > @tier_rank[a || "audit"], do: b, else: a)

  defp impact_unit(nil, sym), do: sym.impact_unit
  defp impact_unit(score, _sym), do: score.impact_unit

  defp muted_ids(items, now) do
    mutes =
      from(m in HumanMute, where: m.expires_at > ^now, select: {m.environment, m.service, m.kind, m.key, m.phenomenon})
      |> Repo.all()
      |> MapSet.new()

    if MapSet.size(mutes) == 0 do
      MapSet.new()
    else
      ids = Enum.map(items, & &1.sym.entity_id)
      entities = Map.new(Repo.all(from(e in Entity, where: e.id in ^ids)), &{&1.id, &1})

      # A mute set from a snapshot whose key `Symptoms.Log.fit/1` trimmed
      # carries the trimmed key, so both forms match.
      for %{sym: sym} <- items,
          e = entities[sym.entity_id],
          Enum.any?(
            Enum.uniq([e.key, Log.trim_key(e.key)]),
            &MapSet.member?(mutes, {e.environment, e.service, e.kind, &1, sym.phenomenon})
          ),
          into: MapSet.new(),
          do: sym.id
    end
  end

  ## Revisions

  defp write(work, stepped, scores, now) do
    ids = work |> Map.values() |> Enum.map(& &1.sym.entity_id)
    entities = Map.new(Repo.all(from(e in Entity, where: e.id in ^ids)), &{&1.id, &1})
    coalesce_seconds = Settings.detector(:coalesce_minutes) * 60

    work
    |> Enum.sort_by(fn {_id, item} -> {item.sym.root_key, item.sym.id} end)
    |> Enum.map_reduce(0, fn {id, item}, count ->
      item = finalize(item, now)
      document = document(item, entities[item.sym.entity_id], stepped, scores, now)
      transition = transition(item, document, now, coalesce_seconds)
      sym = persist(item.sym)

      if transition do
        sym = Log.append!(sym, Map.put(document, "transition", transition), now)
        {{id, %{item | sym: sym}}, count + 1}
      else
        {{id, %{item | sym: sym}}, count}
      end
    end)
    |> then(fn {items, count} -> {Map.new(items), count} end)
  end

  defp finalize(%{hint: :resolve, sym: sym} = item, now) do
    Map.put(item, :sym, %{sym | state: "resolved", resolved_at: now})
  end

  defp finalize(item, _now), do: item

  defp persist(%Symptom{revision: 0} = sym) do
    if Repo.get(Symptom, sym.id), do: update(sym), else: Repo.insert!(sym)
  end

  defp persist(sym), do: update(sym)

  defp update(sym) do
    fields =
      Map.take(sym, [
        :root_key,
        :phenomenon,
        :state,
        :tier,
        :max_tier,
        :score,
        :max_score,
        :p_degraded,
        :expected_cost,
        :impact_unit,
        :impact_rate,
        :merged_into,
        :charged,
        :paged_at,
        :page_logged_at,
        :delayed_until,
        :delay_probability,
        :resolved_at
      ])

    {1, [updated]} =
      Repo.update_all(from(s in Symptom, where: s.id == ^sym.id, select: s), set: Map.to_list(fields))

    updated
  end

  defp transition(%{hint: hint}, _document, _now, _coalesce) when hint in [:opened, :reopened], do: Atom.to_string(hint)
  defp transition(%{sym: %{document: nil}}, _document, _now, _coalesce), do: "opened"

  defp transition(%{sym: sym}, document, now, coalesce_seconds) do
    old = sym.document

    cond do
      old["state"] != document["state"] -> state_transition(document["state"])
      @tier_rank[document["tier"]] > @tier_rank[old["tier"]] -> "escalated"
      @tier_rank[document["tier"]] < @tier_rank[old["tier"]] -> "deescalated"
      material_annotation?(old, document) -> "annotated"
      coalesced?(sym, old, document, now, coalesce_seconds) -> "annotated"
      true -> nil
    end
  end

  defp state_transition("resolved"), do: "resolved"
  defp state_transition("merged"), do: "merged"
  defp state_transition("open"), do: "reopened"

  # Root or merge, outcome or brief, or impact 2× or more.
  defp material_annotation?(old, document) do
    Enum.any?(~w(root merged_into outcome brief_ref), &(old[&1] != document[&1])) or
      impact_changed?(old["impact"], document["impact"])
  end

  defp coalesced?(sym, old, document, now, coalesce_seconds) do
    DateTime.diff(now, sym.last_revision_at, :second) >= coalesce_seconds and
      Map.drop(old, @volatile) != Map.drop(document, @volatile)
  end

  @doc "Whether an impact rate changed by a factor of 2 or more (a change from or to zero counts)."
  @spec impact_changed?(map() | nil, map() | nil) :: boolean()
  def impact_changed?(old, new) do
    ratio_changed?(rate(old), rate(new))
  end

  defp rate(%{"rate" => rate}) when is_number(rate), do: rate
  defp rate(_impact), do: 0.0

  defp ratio_changed?(a, b) when a == 0 and b == 0, do: false
  defp ratio_changed?(a, b) when a == 0 or b == 0, do: true
  defp ratio_changed?(a, b), do: b / a >= 2 or a / b >= 2

  defp document(item, entity, stepped, scores, now) do
    sym = item.sym
    old = sym.document || %{}
    score = scores[sym.entity_id]
    decision = Map.get(item, :decision)

    %{
      "symptom_key" => sym.symptom_key,
      "scope" => %{"kind" => "tuist_ops"},
      "state" => sym.state,
      "merged_into" => sym.merged_into,
      "tier" => sym.tier,
      "phenomenon" => sym.phenomenon,
      "entity" => %{
        "environment" => entity.environment,
        "service" => entity.service,
        "kind" => entity.kind,
        "key" => entity.key
      },
      "title" =>
        String.slice(
          "#{String.replace(sym.phenomenon, "_", " ")} on #{entity.service} #{entity.kind} #{entity.key}",
          0,
          300
        ),
      "phenomena" => phenomena_document(score, old),
      "score" => round4(score_now(stepped[sym.root_key], sym)),
      "p_degraded" => optional(sym.p_degraded, &round4/1),
      "impact" => impact_document(sym),
      "budget_price" => optional(decision, &round4(&1.price)),
      "decision" => decision_document(sym, decision, old),
      "root" => Map.get(item, :root) || old["root"] || own_root(sym),
      "suspected_change" => Deploys.suspected_change(sym.entity_id, now) || old["suspected_change"],
      "evidence" => evidence_document(score, old),
      "board" => old["board"],
      "brief_ref" => old["brief_ref"],
      "outcome" => old["outcome"],
      "opened_at" => DateTime.to_iso8601(sym.opened_at),
      "updated_at" => DateTime.to_iso8601(now),
      "resolved_at" => optional(sym.resolved_at, &DateTime.to_iso8601/1)
    }
  end

  defp optional(nil, _fun), do: nil
  defp optional(value, fun), do: fun.(value)

  defp phenomena_document(nil, old), do: old["phenomena"] || []

  defp phenomena_document(score, _old) do
    Enum.map(score.phenomena, fn p ->
      %{"phenomenon" => to_string(p.phenomenon), "nats" => round4(p.nats), "sources" => p.sources}
    end)
  end

  defp score_now(nil, sym), do: sym.score
  defp score_now(state, _sym), do: max(state.cusum, state.previous)

  defp impact_document(%{impact_unit: nil}), do: nil
  defp impact_document(sym), do: %{"unit" => sym.impact_unit, "rate" => round4(sym.impact_rate || 0.0)}

  defp own_root(sym), do: %{"root_symptom_id" => sym.id, "member_symptom_ids" => [], "shared_cause" => false}

  # `attribute_contrast` (`Symptoms.Contrast`) is written once and kept.
  defp evidence_document(score, old) do
    evidence = %{"series_refs" => [], "example_ids" => example_ids(score, old), "masked_excerpts" => []}

    case get_in(old, ["evidence", "attribute_contrast"]) do
      nil -> evidence
      contrast -> Map.put(evidence, "attribute_contrast", contrast)
    end
  end

  defp example_ids(nil, old), do: get_in(old, ["evidence", "example_ids"]) || []
  defp example_ids(score, _old), do: Enum.take(score.examples, 3)

  defp decision_document(sym, nil, old) do
    Map.merge(old["decision"] || %{}, %{"tier" => sym.tier, "would_page" => false})
  end

  # The delay published is the one stored on the symptom: drawn once when
  # its root was charged a page, or at the board push. The policy's per-window
  # draw for uncharged items is never published, so it cannot churn
  # revisions.
  defp decision_document(sym, decision, _old) do
    %{
      "tier" => sym.tier,
      "would_page" => decision.would_page,
      "delayed_until" => sym.delayed_until && DateTime.to_iso8601(sym.delayed_until),
      "delay_probability" => sym.delay_probability || 0.0
    }
  end

  defp round4(value), do: Float.round(value * 1.0, 4)

  ## Paging

  defp page(work, now) do
    work
    |> Map.values()
    |> Enum.filter(
      &(&1.sym.state != "resolved" and &1.sym.charged and is_nil(&1.sym.paged_at) and is_nil(&1.sym.page_logged_at))
    )
    |> Enum.group_by(& &1.sym.root_key)
    |> Enum.each(fn {key, items} ->
      root = Enum.find(items, &(&1.sym.id == &1.sym.document["root"]["root_symptom_id"])) || hd(items)
      delayed_until = root.sym.delayed_until

      # A delayed page goes out only if the root still pages now: a mute
      # during the delay, or a drop below page tier, holds it back.
      if sendable?(root) and (is_nil(delayed_until) or not DateTime.after?(delayed_until, now)) do
        deliver(key, root.sym, Enum.map(items, & &1.sym.id), now)
      end
    end)
  end

  defp sendable?(item), do: item.sym.tier == "page" and not Map.get(item, :muted, false)

  defp deliver(key, root, ids, now) do
    case Paging.page(root.document, now) do
      {:error, reason} ->
        Store.audit("page_failed", now, symptom_id: root.id, data: %{root_key: key, reason: inspect(reason)})

      # Only a delivered page sets `paged_at`, which labels read as the page
      # time; a page logged with paging off is recorded apart, once.
      delivery ->
        field = if delivery == :sent, do: :paged_at, else: :page_logged_at
        Repo.update_all(from(s in Symptom, where: s.id in ^ids), set: [{field, now}])
        Store.audit("page_#{delivery}", now, symptom_id: root.id, data: %{root_key: key})
    end
  end

  ## Persistence

  defp persist_detectors(stepped, work, window_seconds, window_start, now) do
    roots_with_symptoms =
      for {_, %{sym: sym}} <- work, sym.state != "resolved", into: %{} do
        {sym.root_key, sym.document["root"]["root_symptom_id"]}
      end

    {keep, drop} = Enum.split_with(stepped, fn {key, s} -> s.cusum > 0 or Map.has_key?(roots_with_symptoms, key) end)
    drop_keys = Enum.map(drop, &elem(&1, 0))
    Repo.delete_all(from(d in DetectorState, where: d.root_key in ^drop_keys))

    rows =
      Enum.map(keep, fn {key, s} ->
        %{
          root_key: key,
          cusum: s.cusum,
          window_seconds: window_seconds,
          last_window_start: window_start,
          quiet_windows: s.quiet,
          symptom_id: roots_with_symptoms[key],
          updated_at: now
        }
      end)

    rows
    |> Enum.chunk_every(2_000)
    |> Enum.each(
      &Repo.insert_all(DetectorState, &1,
        on_conflict: {:replace, @detector_fields},
        conflict_target: [:root_key]
      )
    )
  end

  defp persist_root_scores(stepped, roots, work, window_seconds, window_start) do
    root_symptom =
      for {_, %{sym: sym}} <- work, into: %{}, do: {sym.root_key, sym.document["root"]["root_symptom_id"]}

    rows =
      for {key, s} <- stepped, s.cusum > 0 or s.previous > 0 do
        %{
          root_key: key,
          window_seconds: window_seconds,
          window_start: window_start,
          x: s.x,
          score: max(s.cusum, s.previous),
          impact: if(root = roots[key], do: root.impact),
          symptom_id: root_symptom[key]
        }
      end

    rows
    |> Enum.chunk_every(2_000)
    |> Enum.each(
      &Repo.insert_all(RootScore, &1,
        on_conflict: {:replace, [:x, :score, :impact, :symptom_id]},
        conflict_target: [:root_key, :window_seconds, :window_start]
      )
    )
  end

  defp summarize(work, revisions) do
    items = Map.values(work)
    ids_with = fn hint -> for %{hint: ^hint, sym: sym} <- items, do: sym.id end

    %{
      opened: ids_with.(:opened),
      reopened: ids_with.(:reopened),
      resolved: ids_with.(:resolve),
      charged_roots:
        for(%{sym: %{charged: true, state: state, root_key: key}} <- items, state != "resolved", uniq: true, do: key),
      revisions: revisions,
      open_symptoms: for(%{sym: sym} <- items, sym.state != "resolved", into: %{}, do: {sym.entity_id, sym.id})
    }
  end
end
