defmodule Symptoms.Deploys do
  @moduledoc """
  Change events and what they do to detection (README "Deploys").

  - `record_changes/3` stores a source's `changes/2` output. A change's
    category is its optional `:category` (`code`, `config` or `migration`),
    otherwise `code` for a deploy and `config` for a config change. An optional `:retired_entities` list retires the
    entities whose code the change deleted.
  - `prior_terms/2`: a small prior only on the entities a change touched,
    ×1.5 for code, ×2 for configuration, ×3 for a migration,
    decaying linearly to ×1 over 30 minutes; several changes multiply, capped
    at ×3. The pipeline adds `ln(multiplier)` to the entity's combined
    log-evidence.
  - `version_records/2`: for every deploy in the last 2 hours with a new
    version (`after`) and the version it replaced (`before`), each touched
    entity's new-version window is tested against the old version with
    `Symptoms.Evidence.VersionTest` on per-version counts sources store with
    `Symptoms.Store.put_version_counts/2`. When both versions served the
    window the comparison is concurrent (`deploy.version_error_share`);
    otherwise against the old version's last 30 minutes before the deploy
    (`deploy.version_error_share_adjacent`, raw weight 0.5). On windows whose
    counts carry latency histograms (5-minute windows from
    `Symptoms.Sources.PulseTraces`), the same test runs on latency
    exceedance (`deploy.version_latency_exceedance`, `:latency`): the share
    of each version's requests above the old version's p95 bucket, where
    that bucket comes from the old version's 30 minutes before the deploy,
    so it does not depend on the window under test. The running e-process is
    kept per deploy, entity and test, stepped only on concurrent windows, and
    audited when it reaches 20. Adjacent windows give per-window evidence
    only: each compares with the same old-version totals, so multiplying
    them into the e-process would count that data again every window.
  - `reanchor/1`: 2 hours after a deploy, each touched entity is re-anchored
    to the new version unless a symptom on it is open (baselines are frozen
    then; it retries), an independent bad label landed, or the version test
    rejected. A shift above the caps (error share ×3, p95 ×2) never
    re-anchors on its own: it opens an "intended?" board symptom.
  - `resolve_intended/1`: an open "intended?" symptom resolves
    72 hours after it opened (three board pushes), or
    once its outcome is confirmed. Until then it freezes the entity's
    baselines (`Symptoms.Store.baselines_frozen?/1`), but it never tags
    stream windows (`Symptoms.Store.open_symptom_ids/2`).

  Every decision is written to the audit log.
  """

  import Ecto.Query

  alias Symptoms.Evidence.Calibration
  alias Symptoms.Evidence.Statistics
  alias Symptoms.Evidence.VersionTest
  alias Symptoms.Log
  alias Symptoms.Repo
  alias Symptoms.Store
  alias Symptoms.Store.Change
  alias Symptoms.Store.Entity
  alias Symptoms.Store.HumanOutcome
  alias Symptoms.Store.Label
  alias Symptoms.Store.Reanchor
  alias Symptoms.Store.Symptom
  alias Symptoms.Store.VersionCount
  alias Symptoms.Store.VersionTest, as: TestState

  @multipliers %{"code" => 1.5, "config" => 2.0, "migration" => 3.0}
  @cap 3.0
  @decay_seconds 1_800
  @test_seconds 7_200
  @quiet_seconds 7_200
  @give_up_seconds 86_400
  @reference_seconds 1_800
  @error_cap 3.0
  @p95_cap 2.0
  @reject_e 20.0
  @intended_seconds 72 * 3_600

  @doc "The prior multiplier of a change category at its start."
  @spec multiplier(String.t()) :: float()
  def multiplier(category), do: Map.get(@multipliers, category, 1.0)

  @doc """
  The combined multiplier at `at` of `changes` (`[{category, changed_at}]`)
  on one entity: each decays linearly from its category's multiplier to 1
  over 30 minutes, they multiply, and the product is capped at ×3. Changes
  in the future count nothing.
  """
  @spec prior_multiplier([{String.t(), DateTime.t()}], DateTime.t()) :: float()
  def prior_multiplier(changes, at) do
    changes
    |> Enum.map(fn {category, changed_at} ->
      age = DateTime.diff(at, changed_at, :second)

      if age < 0 or age >= @decay_seconds,
        do: 1.0,
        else: 1 + (multiplier(category) - 1) * (1 - age / @decay_seconds)
    end)
    |> Enum.reduce(1.0, &(&1 * &2))
    |> min(@cap)
  end

  @doc "Stores change events from `source`; returns the stored change ids."
  @spec record_changes(String.t(), [map()], DateTime.t()) :: [integer()]
  def record_changes(_source, [], _now), do: []

  def record_changes(source, changes, now) do
    Enum.flat_map(changes, fn change ->
      touched = get(change, :touched_entities) || []
      ids = touched |> Store.resolve_entities(now) |> Map.values()
      Store.retire_entities(get(change, :retired_entities) || [], now)
      kind = to_string(get(change, :kind))

      row = %{
        source: source,
        kind: kind,
        category: to_string(get(change, :category) || default_category(kind)),
        ref: to_string(get(change, :ref)),
        at: Store.usec(get(change, :at)),
        service: get(change, :service),
        touched_entity_ids: Enum.uniq(ids),
        before: version_map(get(change, :before)),
        after: version_map(get(change, :after)),
        inserted_at: now
      }

      case Repo.insert_all(Change, [row],
             on_conflict: :nothing,
             conflict_target: [:source, :kind, :ref],
             returning: [:id]
           ) do
        {1, [%{id: id}]} ->
          Store.audit("change", now, data: Map.take(row, [:source, :kind, :category, :ref, :at, :touched_entity_ids]))
          [id]

        {0, _} ->
          []
      end
    end)
  end

  defp default_category("deploy"), do: "code"
  defp default_category(_), do: "config"

  defp version_map(nil), do: nil
  defp version_map(%{} = map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
  defp version_map(value) when is_binary(value), do: %{"version" => value}
  # Any other value: kept as is under `value`.
  defp version_map(value), do: %{"value" => value}

  defp version(nil), do: nil
  defp version(%{"version" => v}) when is_binary(v), do: v
  defp version(_), do: nil

  @doc """
  Deploys of the last 30 minutes before `now` as `Symptoms.Sources.Source`
  changes (`kind`, `ref`, `service`, `at` in Unix seconds), for sources that
  discount deploy-introduced novelty.
  """
  @spec recent_deploys(DateTime.t()) :: [map()]
  def recent_deploys(now) do
    since = DateTime.shift(now, second: -@decay_seconds)

    from(c in Change, where: c.kind == "deploy" and c.at > ^since and c.at <= ^now, order_by: c.at)
    |> Repo.all()
    |> Enum.map(&%{kind: :deploy, ref: &1.ref, service: &1.service, at: DateTime.to_unix(&1.at)})
  end

  @doc "`%{entity_id => ln(prior_multiplier)}` for `entity_ids` at `at`, only for touched entities."
  @spec prior_terms([integer()], DateTime.t()) :: %{optional(integer()) => float()}
  def prior_terms(entity_ids, at) do
    since = DateTime.shift(at, second: -@decay_seconds)

    from(c in Change, where: c.at > ^since and c.at <= ^at, select: {c.category, c.at, c.touched_entity_ids})
    |> Repo.all()
    |> Enum.flat_map(fn {category, changed_at, ids} -> Enum.map(ids, &{&1, {category, changed_at}}) end)
    |> Enum.filter(fn {id, _} -> id in entity_ids end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {id, changes} -> {id, :math.log(prior_multiplier(changes, at))} end)
  end

  @doc """
  Version-test evidence for the window: rows with `entity_id`, `phenomenon`
  (`"request_errors"` or `"latency"`), `source`, `statistic` (ln of the
  window's e-value) and `e` (capped), in the same storage format as the
  pipeline's calibrated source rows.
  """
  @spec version_records(pos_integer(), DateTime.t()) :: [map()]
  def version_records(window_seconds, window_start) do
    since = DateTime.shift(window_start, second: -@test_seconds)

    deploys =
      Repo.all(
        from(c in Change,
          where:
            c.kind == "deploy" and c.at > ^since and c.at <= ^window_start and not is_nil(c.after) and
              not is_nil(c.before)
        )
      )

    for change <- deploys,
        new = version(change.after),
        old = version(change.before),
        new && old,
        entity_id <- change.touched_entity_ids,
        row <- version_window(change, entity_id, new, old, window_seconds, window_start),
        do: row
  end

  defp version_window(change, entity_id, new, old, window_seconds, window_start) do
    counts =
      from(v in VersionCount,
        where:
          v.entity_id == ^entity_id and v.window_seconds == ^window_seconds and v.window_start == ^window_start and
            v.version in ^[new, old]
      )
      |> Repo.all()
      |> Map.new(&{&1.version, &1})

    reference = reference_counts(entity_id, old, window_seconds, change.at)
    concurrent = match?(%{total: total} when total > 0, counts[old])

    error_row(change, entity_id, counts[new], counts[old], reference, concurrent, window_seconds, window_start) ++
      latency_row(change, entity_id, counts[new], counts[old], reference, concurrent, window_seconds, window_start)
  end

  defp error_row(change, entity_id, new_counts, old_counts, reference, concurrent, window_seconds, window_start) do
    {x_new, n_new} = if new_counts, do: {new_counts.errors, new_counts.total}, else: {0, 0}

    {source, {x_old, n_old}} =
      if concurrent,
        do: {"deploy.version_error_share", {old_counts.errors, old_counts.total}},
        else: {"deploy.version_error_share_adjacent", {reference.errors, reference.total}}

    counts = {x_new, n_new, x_old, n_old}

    window_row(change, entity_id, "error_share", counts, window_seconds, window_start,
      step: concurrent,
      phenomenon: :request_errors,
      source: source,
      impact_unit: "failed_requests_per_min"
    )
  end

  # Latency needs the new version's histogram and the old version's p95
  # bucket from its 30 minutes before the deploy.
  defp latency_row(change, entity_id, new_counts, old_counts, reference, concurrent, window_seconds, window_start) do
    with %{histogram: %{} = new_histogram} <- new_counts,
         threshold when is_integer(threshold) <- Statistics.quantile_bucket(reference.histogram, 0.95) do
      both = concurrent and is_map(old_counts.histogram)

      {source, old_histogram} =
        if both,
          do: {"deploy.version_latency_exceedance", histogram(old_counts.histogram)},
          else: {"deploy.version_latency_exceedance_adjacent", reference.histogram}

      counts = VersionTest.exceedance_counts(histogram(new_histogram), old_histogram, threshold)

      window_row(change, entity_id, "latency_exceedance", counts, window_seconds, window_start,
        step: both,
        phenomenon: :latency,
        source: source,
        impact_unit: "slow_requests_per_min"
      )
    else
      _ -> []
    end
  end

  defp window_row(change, entity_id, test, {x_new, n_new, x_old, n_old} = counts, window_seconds, window_start, attrs) do
    if n_new > 0 and n_old > 0 do
      log_e = VersionTest.window_log_e(x_new, n_new, x_old, n_old)
      if attrs[:step], do: step_test(change, entity_id, test, counts, window_start)

      [
        %{
          entity_id: entity_id,
          phenomenon: Atom.to_string(attrs[:phenomenon]),
          source: attrs[:source],
          window_seconds: window_seconds,
          window_start: window_start,
          statistic: log_e,
          p: nil,
          e: if(log_e >= :math.log(Calibration.cap()), do: Calibration.cap(), else: :math.exp(log_e)),
          observed: x_new / n_new,
          expected: x_old / n_old,
          n: n_new,
          impact_unit: attrs[:impact_unit],
          impact_rate: x_new * 60 / window_seconds,
          examples: []
        }
      ]
    else
      []
    end
  end

  # The old version's 30 minutes before the deploy: summed counts and histogram.
  defp reference_counts(entity_id, old, window_seconds, changed_at) do
    from_at = DateTime.shift(changed_at, second: -@reference_seconds)

    rows =
      Repo.all(
        from(v in VersionCount,
          where:
            v.entity_id == ^entity_id and v.version == ^old and v.window_seconds == ^window_seconds and
              v.window_start >= ^from_at and v.window_start < ^changed_at,
          select: {v.errors, v.total, v.histogram}
        )
      )

    %{
      errors: rows |> Enum.map(&elem(&1, 0)) |> Enum.sum(),
      total: rows |> Enum.map(&elem(&1, 1)) |> Enum.sum(),
      histogram:
        rows
        |> Enum.map(&elem(&1, 2))
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&histogram/1)
        |> Statistics.merge_histograms()
    }
  end

  # Histograms are stored as JSON, with string bucket keys.
  defp histogram(stored), do: Map.new(stored, fn {bucket, count} -> {to_integer(bucket), count} end)

  defp to_integer(bucket) when is_integer(bucket), do: bucket
  defp to_integer(bucket) when is_binary(bucket), do: String.to_integer(bucket)

  defp test_state(change, entity_id, test) do
    Repo.one(from(t in TestState, where: t.change_id == ^change.id and t.entity_id == ^entity_id and t.test == ^test)) ||
      %TestState{change_id: change.id, entity_id: entity_id, test: test, log_weights: VersionTest.initial(), e: 1.0}
  end

  defp step_test(change, entity_id, test, {x_new, n_new, x_old, n_old}, window_start) do
    state = test_state(change, entity_id, test)

    if state.last_window_start == nil or DateTime.before?(state.last_window_start, window_start) do
      weights = VersionTest.update(state.log_weights, x_new, n_new, x_old, n_old)
      log_e = VersionTest.log_e_value(weights)
      # `e` is a finite compatibility/display value. The full process stays
      # in log_weights; never use the saturated value for rejection.
      e = VersionTest.e_value(weights)
      rejected = state.status == "running" and log_e >= :math.log(@reject_e)

      Repo.insert_all(
        TestState,
        [
          %{
            change_id: change.id,
            entity_id: entity_id,
            test: test,
            log_weights: weights,
            e: e,
            status: if(rejected, do: "rejected", else: state.status || "running"),
            last_window_start: window_start,
            updated_at: window_start
          }
        ],
        on_conflict: {:replace, [:log_weights, :e, :status, :last_window_start, :updated_at]},
        conflict_target: [:change_id, :entity_id, :test]
      )

      if rejected do
        Store.audit("version_test_rejected", window_start,
          entity_id: entity_id,
          data: %{change_ref: change.ref, test: test, e: e, log_e: log_e}
        )
      end
    end
  end

  @doc """
  The most recent change that touched `entity_id` in the 2 hours before
  `at`, as the snapshot's `suspected_change`, or `nil`.
  """
  @spec suspected_change(integer(), DateTime.t()) :: map() | nil
  def suspected_change(entity_id, at) do
    since = DateTime.shift(at, second: -@test_seconds)

    from(c in Change,
      where: c.at > ^since and c.at <= ^at and ^entity_id in c.touched_entity_ids,
      order_by: [desc: c.at],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil ->
        nil

      change ->
        touched =
          Repo.all(
            from(e in Entity,
              where: e.id in ^Enum.take(change.touched_entity_ids, 20),
              select: %{"environment" => e.environment, "service" => e.service, "kind" => e.kind, "key" => e.key}
            )
          )

        %{
          "kind" => if(change.kind in ~w(deploy config), do: change.kind, else: "deploy"),
          "ref" => change.ref,
          "at" => DateTime.to_iso8601(change.at),
          "touched_entities" => touched
        }
    end
  end

  @doc """
  Resolves open "intended?" symptoms that opened at least
  #{div(@intended_seconds, 3_600)} hours before `now` or whose outcome is
  confirmed, each with a `resolved` revision. Returns their ids.
  """
  @spec resolve_intended(DateTime.t()) :: [String.t()]
  def resolve_intended(now) do
    expired = DateTime.shift(now, second: -@intended_seconds)

    from(s in Symptom,
      left_join: o in HumanOutcome,
      on: o.symptom_id == s.id,
      where: s.kind == "intended" and s.state == "open",
      where: s.opened_at <= ^expired or not is_nil(o.symptom_id),
      select: s.id
    )
    |> Repo.all()
    |> Enum.map(fn id ->
      {:ok, _} = Repo.transaction(fn -> resolve_open(id, now) end)
      id
    end)
  end

  # Under the log lock, so the resolution builds on the latest snapshot.
  defp resolve_open(id, now) do
    Log.lock!()
    symptom = Repo.one!(from(s in Symptom, where: s.id == ^id, lock: "FOR UPDATE"))

    if symptom.state == "open" do
      {1, [symptom]} =
        Repo.update_all(from(s in Symptom, where: s.id == ^id, select: s),
          set: [state: "resolved", resolved_at: now, updated_at: now]
        )

      at = DateTime.to_iso8601(now)

      document =
        symptom.document
        |> Map.drop(~w(seq revision schema_version symptom_id))
        |> Map.merge(%{"state" => "resolved", "transition" => "resolved", "resolved_at" => at, "updated_at" => at})

      Log.append!(symptom, document, now)
    end
  end

  @doc """
  Decides re-anchoring for deploys at least 2 hours old (see the module
  doc). Returns the decisions made, as `{status, change_id, entity_id}`.
  """
  @spec reanchor(DateTime.t()) :: [{String.t(), integer(), integer()}]
  def reanchor(now) do
    until = DateTime.shift(now, second: -@quiet_seconds)
    since = DateTime.shift(now, second: -(@quiet_seconds + @give_up_seconds))

    decided =
      MapSet.new(Repo.all(from(r in Reanchor, select: {r.change_id, r.entity_id})))

    from(c in Change,
      where: c.kind == "deploy" and c.at <= ^until and c.at > ^since and not is_nil(c.after)
    )
    |> Repo.all()
    |> Enum.flat_map(fn change ->
      for entity_id <- change.touched_entity_ids,
          not MapSet.member?(decided, {change.id, entity_id}),
          decision = decide_reanchor(change, entity_id, now),
          decision != :pending,
          do: decision
    end)
  end

  defp decide_reanchor(change, entity_id, now) do
    new = version(change.after)
    old = version(change.before)
    {error_ratio, p95_ratio, served} = ratios(entity_id, new, old, change.at, now)
    stale = DateTime.diff(now, change.at) >= @quiet_seconds + @give_up_seconds - 60

    case reanchor_status(change, entity_id, served, {error_ratio, p95_ratio}, stale) do
      :pending -> :pending
      status -> record_reanchor(status, change, entity_id, {old, new}, {error_ratio, p95_ratio}, now)
    end
  end

  # A frozen baseline or a deploy without traffic on both versions waits,
  # until the deploy is a day old.
  defp reanchor_status(change, entity_id, served, {error_ratio, p95_ratio}, stale) do
    waiting = if stale, do: "blocked", else: :pending

    cond do
      Store.baselines_frozen?(entity_id) -> waiting
      bad_label_since?(entity_id, change.at) or test_rejected?(change.id, entity_id) -> "blocked"
      not served -> waiting
      above_caps?(error_ratio, p95_ratio) -> "intended"
      true -> "accepted"
    end
  end

  defp record_reanchor(status, change, entity_id, {old, new}, {error_ratio, p95_ratio}, now) do
    symptom_id =
      if status == "intended", do: open_intended(change, entity_id, error_ratio, p95_ratio, now)

    Repo.insert_all(Reanchor, [
      %{
        entity_id: entity_id,
        change_id: change.id,
        from_version: old,
        to_version: new,
        status: status,
        error_ratio: error_ratio,
        p95_ratio: p95_ratio,
        symptom_id: symptom_id,
        at: now
      }
    ])

    Store.audit("reanchor", now,
      entity_id: entity_id,
      symptom_id: symptom_id,
      data: %{
        status: status,
        change_ref: change.ref,
        from: old,
        to: new,
        error_ratio: error_ratio,
        p95_ratio: p95_ratio
      }
    )

    {status, change.id, entity_id}
  end

  defp above_caps?(error_ratio, p95_ratio), do: (error_ratio || 0) > @error_cap or (p95_ratio || 0) > @p95_cap

  defp ratios(entity_id, new, old, changed_at, now) do
    reference_from = DateTime.shift(changed_at, second: -@quiet_seconds)

    rows =
      Repo.all(
        from(v in VersionCount,
          where:
            v.entity_id == ^entity_id and
              ((v.version == ^new and v.window_start >= ^changed_at and v.window_start < ^now) or
                 (v.version == ^old and v.window_start >= ^reference_from and v.window_start < ^changed_at)),
          select: {v.version, v.errors, v.total, v.p95_ms, v.window_seconds}
        )
      )

    # Error shares from the shortest windows only, so 1- and 5-minute counts
    # of the same requests are not added together.
    shortest = rows |> Enum.map(&elem(&1, 4)) |> Enum.min(fn -> 60 end)
    {new_rows, old_rows} = Enum.split_with(rows, &(elem(&1, 0) == new))

    {new_counts, old_counts} =
      {Enum.filter(new_rows, &(elem(&1, 4) == shortest)), Enum.filter(old_rows, &(elem(&1, 4) == shortest))}

    share = fn list -> (sum(list, 1) + 0.5) / (sum(list, 2) + 1) end
    served = sum(new_counts, 2) > 0 and sum(old_counts, 2) > 0

    error_ratio = if served, do: share.(new_counts) / share.(old_counts)
    {error_ratio, p95_ratio(median_p95(new_rows), median_p95(old_rows)), served}
  end

  defp p95_ratio(new, old) when is_number(new) and is_number(old) and old > 0, do: new / old
  defp p95_ratio(_new, _old), do: nil

  defp sum(rows, index), do: rows |> Enum.map(&elem(&1, index)) |> Enum.sum()

  defp median_p95(rows) do
    case rows |> Enum.map(&elem(&1, 3)) |> Enum.reject(&is_nil/1) do
      [] -> nil
      values -> Statistics.median(values)
    end
  end

  defp bad_label_since?(entity_id, at) do
    Repo.exists?(
      from(l in Label,
        join: s in Symptom,
        on: s.id == l.symptom_id,
        where: s.entity_id == ^entity_id and l.outcome == "bad" and l.independent and l.confirmed_at >= ^at
      )
    )
  end

  defp test_rejected?(change_id, entity_id) do
    Repo.exists?(
      from(t in TestState, where: t.change_id == ^change_id and t.entity_id == ^entity_id and t.status == "rejected")
    )
  end

  defp open_intended(change, entity_id, error_ratio, p95_ratio, now) do
    entity = Repo.get!(Entity, entity_id)
    tuple = {entity.environment, entity.service, entity.kind, entity.key}
    id = Log.uuid7(now)

    shift =
      [
        error_ratio && error_ratio > @error_cap && "error share ×#{Float.round(error_ratio, 1)}",
        p95_ratio && p95_ratio > @p95_cap && "p95 ×#{Float.round(p95_ratio, 1)}"
      ]
      |> Enum.filter(&is_binary/1)
      |> Enum.join(", ")

    symptom = %Symptom{
      id: id,
      symptom_key: Log.symptom_key(tuple, "intended_shift"),
      kind: "intended",
      root_key: "intended:#{change.id}:#{entity_id}",
      entity_id: entity_id,
      phenomenon: "request_errors",
      state: "open",
      tier: "board",
      max_tier: "board",
      opened_at: now,
      inserted_at: now,
      updated_at: now
    }

    document = %{
      "symptom_key" => symptom.symptom_key,
      "scope" => %{"kind" => "tuist_ops"},
      "state" => "open",
      "merged_into" => nil,
      "tier" => "board",
      "transition" => "opened",
      "phenomenon" => symptom.phenomenon,
      "entity" => %{
        "environment" => entity.environment,
        "service" => entity.service,
        "kind" => entity.kind,
        "key" => entity.key
      },
      "title" => "Deploy #{change.ref} shifted #{entity.kind} #{entity.key} (#{shift}): intended?",
      "phenomena" => [],
      "score" => 0.0,
      "p_degraded" => nil,
      "impact" => nil,
      "budget_price" => nil,
      "decision" => %{"tier" => "board", "would_page" => false, "delayed_until" => nil, "delay_probability" => 0.0},
      "root" => %{"root_symptom_id" => id, "member_symptom_ids" => [], "shared_cause" => false},
      "suspected_change" => suspected_change(entity_id, change.at),
      "evidence" => %{"series_refs" => [], "example_ids" => [], "masked_excerpts" => []},
      "brief_ref" => nil,
      "outcome" => nil,
      "opened_at" => DateTime.to_iso8601(now),
      "updated_at" => DateTime.to_iso8601(now),
      "resolved_at" => nil
    }

    Repo.transaction(fn ->
      Log.lock!()
      Repo.insert!(symptom)
      Log.append!(symptom, document, now)
    end)

    id
  end

  defp get(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
