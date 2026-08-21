defmodule Tuist.Automations.Holds.Hold do
  @moduledoc """
  A row in the `test_case_state_holds` ClickHouse ledger: one `claim` or
  `withdraw` operation by an owner (`alert_id`) on a test case.

  The ledger is append-only; an owner's current position is its latest row
  (`argMax` over `inserted_at`), and a claim is live iff that row's `op` is
  `claim`. `state` is meaningful on claim rows only. ClickHouse enforces no
  invariants, so the changeset carries them all.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @ops ~w(claim withdraw)
  @states ~w(enabled muted skipped)
  @expiry_kinds ~w(none days runs)

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_case_state_holds" do
    field :project_id, Ch, type: "Int64"
    field :alert_id, Ecto.UUID
    field :test_case_id, Ecto.UUID
    field :op, Ch, type: "LowCardinality(String)"
    field :state, Ch, type: "LowCardinality(String)", default: ""
    field :placed_at, Ch, type: "DateTime64(6)"
    field :actor_id, Ch, type: "Nullable(Int64)"
    field :expiry_kind, Ch, type: "LowCardinality(String)", default: "none"
    field :expires_at, Ch, type: "Nullable(DateTime64(6))"
    field :expiry_runs, Ch, type: "Nullable(Int32)"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end

  def changeset(hold, attrs) do
    hold
    |> cast(attrs, [
      :id,
      :project_id,
      :alert_id,
      :test_case_id,
      :op,
      :state,
      :placed_at,
      :actor_id,
      :expiry_kind,
      :expires_at,
      :expiry_runs,
      :inserted_at
    ])
    |> validate_required([:id, :project_id, :alert_id, :test_case_id, :op, :placed_at, :inserted_at])
    |> validate_inclusion(:op, @ops)
    |> validate_inclusion(:expiry_kind, @expiry_kinds)
    |> validate_claim_state()
    |> validate_expiry_pairing()
  end

  defp validate_claim_state(changeset) do
    if get_field(changeset, :op) == "claim" do
      changeset
      |> validate_required([:state])
      |> validate_inclusion(:state, @states)
      |> validate_enabled_requires_actor()
    else
      changeset
    end
  end

  # Only the Manual (human) tier may claim `enabled`; rules can only hold a
  # test in a degraded state.
  defp validate_enabled_requires_actor(changeset) do
    if get_field(changeset, :state) == "enabled" and is_nil(get_field(changeset, :actor_id)) do
      add_error(changeset, :state, "enabled claims require an actor")
    else
      changeset
    end
  end

  defp validate_expiry_pairing(changeset) do
    case get_field(changeset, :expiry_kind) do
      "days" ->
        changeset
        |> validate_expiry_present(:expires_at, "days")
        |> validate_expiry_absent(:expiry_runs, "days")

      "runs" ->
        changeset
        |> validate_expiry_present(:expiry_runs, "runs")
        |> validate_expiry_absent(:expires_at, "runs")

      "none" ->
        if is_nil(get_field(changeset, :expires_at)) and is_nil(get_field(changeset, :expiry_runs)) do
          changeset
        else
          add_error(changeset, :expiry_kind, "none expiry does not take expiry fields")
        end

      _ ->
        changeset
    end
  end

  defp validate_expiry_present(changeset, field, kind) do
    if is_nil(get_field(changeset, field)) do
      add_error(changeset, field, "is required for a #{kind} expiry")
    else
      changeset
    end
  end

  defp validate_expiry_absent(changeset, field, kind) do
    if is_nil(get_field(changeset, field)) do
      changeset
    else
      add_error(changeset, field, "must be nil for a #{kind} expiry")
    end
  end
end
