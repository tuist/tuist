defmodule Tuist.Kura.OriginRollup do
  @moduledoc """
  One account's cache traffic from one origin on one UTC day.

  The whole persisted form of the origin signal. Everything finer than this —
  the address, the request, the user — was discarded in the request path that
  counted it.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  schema "kura_origin_rollups" do
    field :origin, :string
    field :date, :date
    field :run_count, :integer, default: 0
    field :demand_count, :integer, default: 0

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def changeset(rollup, attrs) do
    rollup
    |> cast(attrs, [:account_id, :origin, :date, :run_count, :demand_count])
    |> validate_required([:account_id, :origin, :date])
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :origin, :date])
  end
end
