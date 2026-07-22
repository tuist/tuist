defmodule Tuist.Kura.Rollout do
  @moduledoc """
  One rollout of one Kura runtime image tag across this environment's
  managed fleet (spec #79).

  A rollout is durable control-plane state advanced one reconciler tick at
  a time: which wave it is in, when the wave started, since when the wave
  has been continuously healthy, and why it paused. At most one rollout is
  non-terminal (`:running`/`:paused`) at a time; a new tag supersedes the
  active rollout.

      running ⇄ paused
         │        │
         │        └→ aborted
         ├→ completed
         └→ superseded   (also reachable from paused)

  `mode` decides pacing: `:progressive` runs the account-grouped waves with
  the health gate between them; `:expedited` is the all-at-once fan-out
  (today's behavior), used by the canary/staging environments, rollbacks to
  a proven tag, and operator expedites during incidents.

  `baseline_image_tag` is the tag the fleet was on when this rollout was
  created. Servers created mid-rollout provision on it until their
  account's wave completes, so a paused-as-suspect version never reaches
  fresh servers.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Kura.RolloutEvent
  alias Tuist.Kura.RolloutServer
  alias Tuist.Kura.RolloutWaveAssignment

  @status_mappings [running: 0, paused: 1, completed: 2, aborted: 3, superseded: 4]
  @statuses Keyword.keys(@status_mappings)
  @mode_mappings [progressive: 0, expedited: 1]
  @allowed_status_transitions %{
    running: [:running, :paused, :completed, :aborted, :superseded],
    paused: [:paused, :running, :aborted, :superseded],
    completed: [:completed],
    aborted: [:aborted],
    superseded: [:superseded]
  }
  @image_tag_format ~r/\A[A-Za-z0-9_][A-Za-z0-9_.-]*\z/
  @image_tag_message "must be a valid OCI image tag like sha-abcdef123456, latest, or 0.5.2"

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "kura_rollouts" do
    field :image_tag, :string
    field :baseline_image_tag, :string
    field :status, Ecto.Enum, values: @status_mappings, default: :running
    field :mode, Ecto.Enum, values: @mode_mappings, default: :progressive
    field :current_wave, :integer, default: 0
    field :wave_started_at, :utc_datetime
    field :wave_healthy_since, :utc_datetime
    field :paused_at, :utc_datetime
    field :pause_reason, :string
    field :completed_at, :utc_datetime

    has_many :wave_assignments, RolloutWaveAssignment, foreign_key: :kura_rollout_id
    has_many :rollout_servers, RolloutServer, foreign_key: :kura_rollout_id
    has_many :events, RolloutEvent, foreign_key: :kura_rollout_id

    # Sub-second precision so a supersede chain created in quick
    # succession keeps a deterministic latest-rollout order.
    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  def create_changeset(rollout \\ %__MODULE__{}, attrs) do
    rollout
    |> cast(attrs, [:image_tag, :baseline_image_tag, :mode])
    |> validate_required([:image_tag, :mode])
    |> validate_format(:image_tag, @image_tag_format, message: @image_tag_message)
    |> validate_length(:image_tag, max: 128)
    |> unique_constraint([:status],
      name: :kura_rollouts_single_active_index,
      message: "another Kura rollout is already active"
    )
  end

  def update_changeset(rollout, attrs) do
    rollout
    |> cast(attrs, [
      :status,
      :mode,
      :current_wave,
      :wave_started_at,
      :wave_healthy_since,
      :paused_at,
      :pause_reason,
      :completed_at
    ])
    |> validate_required([:status, :mode, :current_wave])
    |> validate_number(:current_wave, greater_than_or_equal_to: 0)
    |> validate_status_transition()
  end

  defp validate_status_transition(%Ecto.Changeset{errors: errors} = changeset) do
    if Keyword.has_key?(errors, :status) do
      changeset
    else
      from = changeset.data.status || :running
      to = get_field(changeset, :status)

      if to in Map.get(@allowed_status_transitions, from, []) do
        changeset
      else
        add_error(changeset, :status, "cannot transition from #{from} to #{to}")
      end
    end
  end
end
