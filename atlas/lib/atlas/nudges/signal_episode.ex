defmodule Atlas.Nudges.SignalEpisode do
  @moduledoc """
  Per-account, per-signal episode tracking. A signal opens an episode when
  its threshold is first crossed; the nudge fires only on episode open, not
  while the episode is open. The episode closes when the metric recovers.

  This is the edge-trigger primitive that stops a persistently bad account
  from producing a new nudge every evaluation cycle.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account

  @states ~w(open closed)

  schema "nudge_signal_episodes" do
    field :signal, :string
    field :state, :string, default: "open"
    field :opened_at, :utc_datetime
    field :closed_at, :utc_datetime
    field :evidence, :map, default: %{}

    belongs_to :account, Account

    timestamps()
  end

  def states, do: @states

  def open_changeset(episode, attrs) do
    episode
    |> cast(attrs, [:account_id, :signal, :evidence])
    |> put_change(:state, "open")
    |> put_change(:opened_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> validate_required([:account_id, :signal])
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :signal],
      name: :nudge_signal_episodes_open_index
    )
    |> check_constraint(:state, name: :nudge_signal_episodes_state_check)
  end

  def close_changeset(%__MODULE__{state: "open"} = episode) do
    episode
    |> change(%{
      state: "closed",
      closed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  def close_changeset(episode) do
    episode |> change() |> add_error(:state, "must be open to close")
  end
end
