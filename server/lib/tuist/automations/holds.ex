defmodule Tuist.Automations.Holds do
  @moduledoc """
  Hold ledger for test-case state.

  Claims are standing positions an owner (an automation alert, including the
  per-project Manual automation for humans) takes on a test case's state.
  They are stored as append-only `claim`/`withdraw` rows in the
  `test_case_state_holds` ClickHouse table; an owner's current position is
  its latest row, and the effective state of a test is derived from the set
  of live claims with `derive/1`.
  """
  import Ecto.Query

  alias Tuist.Automations.Holds.Hold
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Tests

  @doc """
  Appends a claim row for `(alert, test_case_id)`.

  `attrs` carries `:state` (required), optional `:actor_id`, and optional
  expiry fields (`:expiry_kind`, `:expires_at`, `:expiry_runs`). `:id`,
  `:placed_at`, and `:inserted_at` may be provided explicitly (backfills use
  deterministic ids and historical timestamps); they default to a random UUID
  and now.
  """
  def place_claim(alert, test_case_id, attrs) do
    append(alert, test_case_id, "claim", Map.new(attrs))
  end

  @doc """
  Appends a withdraw row for `(alert, test_case_id)`.

  Idempotent by semantics: withdrawing with no prior claim just means the
  owner has no live claim. `opts` may carry `:actor_id`.
  """
  def withdraw_claim(alert, test_case_id, opts \\ []) do
    attrs =
      case Keyword.get(opts, :actor_id) do
        nil -> %{}
        actor_id -> %{actor_id: actor_id}
      end

    append(alert, test_case_id, "withdraw", attrs)
  end

  defp append(alert, test_case_id, op, attrs) do
    now = DateTime.utc_now()

    attrs =
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          project_id: alert.project_id,
          alert_id: alert.id,
          test_case_id: test_case_id,
          op: op,
          placed_at: now,
          inserted_at: now
        },
        attrs
      )

    %Hold{}
    |> Hold.changeset(attrs)
    |> IngestRepo.insert()
  end

  @doc """
  Returns a map of `test_case_id => [live claim]` for the given test cases.

  A claim is live iff the owner's latest ledger row is a `claim`. Test cases
  with no live claims are absent from the map.
  """
  def current_claims(project_id, test_case_ids) do
    Hold
    |> where([h], h.project_id == ^project_id and h.test_case_id in ^test_case_ids)
    |> live_claims()
    |> Enum.group_by(& &1.test_case_id)
  end

  @doc """
  Returns the alert's live claims across all its test cases.
  """
  def live_claims_for_alert(alert) do
    Hold
    |> where([h], h.project_id == ^alert.project_id and h.alert_id == ^alert.id)
    |> live_claims()
  end

  defp live_claims(query) do
    # Nullable columns need the tuple wrap: a bare `argMax(actor_id, ...)`
    # skips NULL arguments and would resurrect a stale non-NULL value from an
    # older row. A tuple is never NULL, so `argMax` keeps the latest row.
    query
    |> group_by([h], [h.test_case_id, h.alert_id])
    |> having([h], fragment("argMax(?, ?) = 'claim'", h.op, h.inserted_at))
    |> select([h], %{
      test_case_id: h.test_case_id,
      alert_id: h.alert_id,
      state: fragment("argMax(?, ?)", h.state, h.inserted_at),
      placed_at: fragment("argMax(?, ?)", h.placed_at, h.inserted_at),
      actor_id: fragment("tupleElement(argMax(tuple(?), ?), 1)", h.actor_id, h.inserted_at),
      expiry_kind: fragment("argMax(?, ?)", h.expiry_kind, h.inserted_at),
      expires_at: fragment("tupleElement(argMax(tuple(?), ?), 1)", h.expires_at, h.inserted_at),
      expiry_runs: fragment("tupleElement(argMax(tuple(?), ?), 1)", h.expiry_runs, h.inserted_at)
    })
    |> ClickHouseRepo.all()
  end

  @doc """
  Recomputes the derived state for the given test cases and appends a state
  event only where it differs from the currently projected state.

  This is the single choke point between the claims ledger and the test-case
  state ledger: it folds the live claims per test case with `derive/1`,
  compares against `Tuist.Tests.get_test_case_states/2`, and emits through
  `Tuist.Tests.update_test_case/3` (event append, PubSub, event-driven
  automations, webhooks) only on change — shadowed-claim churn stays silent.

  `cause` carries the provenance of the hold operation that triggered the
  re-derivation: `:alert_id` and/or `:actor_id` are forwarded onto any
  emitted event.

  Idempotent by construction: with no claim changes, derived equals
  projected and nothing is emitted, so it doubles as crash repair — any
  stale projection is converged by the next invocation.

  Returns `{:ok, %{changed: test_case_ids, unchanged_count: count}}`.
  """
  def derive_and_apply(project_id, test_case_ids, cause \\ []) do
    claims = current_claims(project_id, test_case_ids)
    projected = Tests.get_test_case_states(project_id, test_case_ids)
    update_opts = Keyword.take(cause, [:alert_id, :actor_id])

    changed =
      Enum.filter(test_case_ids, fn test_case_id ->
        derived_state = derive(Map.get(claims, test_case_id, [])).state

        derived_state != projected[test_case_id].state and
          apply_derived_state(test_case_id, derived_state, update_opts)
      end)

    {:ok, %{changed: changed, unchanged_count: length(test_case_ids) - length(changed)}}
  end

  # A test case that no longer resolves (e.g. absent from `test_cases`) is
  # left for a later re-derivation rather than failing the whole batch.
  defp apply_derived_state(test_case_id, state, opts) do
    case Tests.update_test_case(test_case_id, %{state: state}, opts) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Derives the effective state of one test case from its list of live claims.

  A claim with an `actor_id` belongs to the human (Manual) tier and wins
  outright; otherwise the most severe rule claim wins (`skipped` over
  `muted`); no claims means `enabled`.

  Returns `%{state: state, held_by: held_by, winning_claim: claim_or_nil}`
  with `held_by` in `"none" | "rules" | "human"`.
  """
  def derive(claims) do
    {human_claims, rule_claims} = Enum.split_with(claims, &(&1.actor_id != nil))

    cond do
      human_claims != [] ->
        winner = Enum.max_by(human_claims, & &1.placed_at, NaiveDateTime)
        %{state: winner.state, held_by: "human", winning_claim: winner}

      rule_claims != [] ->
        winner = Enum.max_by(rule_claims, &severity(&1.state))
        %{state: winner.state, held_by: "rules", winning_claim: winner}

      true ->
        %{state: "enabled", held_by: "none", winning_claim: nil}
    end
  end

  defp severity("skipped"), do: 2
  defp severity("muted"), do: 1
  defp severity(_), do: 0
end
