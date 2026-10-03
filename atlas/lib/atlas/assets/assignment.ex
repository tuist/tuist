defmodule Atlas.Assets.Assignment do
  @moduledoc """
  A custody interval: which user held a given asset over which range of dates.

  Assignments are opened and closed exclusively through the lifecycle
  functions in `Atlas.Assets`. Direct schema mutation is discouraged;
  the context enforces the "one open assignment per asset" invariant and
  overlap policy inside a database transaction with a row-level lock.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Assets.Asset
  alias Atlas.Assets.Assignment
  alias Atlas.Users.User

  @derive {
    Flop.Schema,
    filterable: [:asset_id, :user_id], sortable: [:assigned_on, :inserted_at], default_limit: 50, max_limit: 200
  }

  schema "asset_assignments" do
    belongs_to :asset, Asset
    belongs_to :user, User

    field :user_label_snapshot, :string
    field :assigned_on, :date
    field :returned_on, :date
    field :notes, :string

    timestamps()
  end

  @doc """
  Changeset used to open a new custody interval. `returned_on` is not cast
  here; assignments are closed by the context via `close_changeset/2`.
  """
  def open_changeset(%Assignment{} = assignment, attrs) do
    assignment
    |> cast(attrs, [:asset_id, :user_id, :user_label_snapshot, :assigned_on, :notes])
    |> validate_required([:asset_id, :user_id, :user_label_snapshot, :assigned_on])
    |> foreign_key_constraint(:asset_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:asset_id,
      name: :asset_assignments_open_per_asset_index,
      message: "already has an open assignment"
    )
    |> check_constraint(:returned_on,
      name: :asset_assignments_returned_after_assigned,
      message: "must be on or after the assignment date"
    )
  end

  @doc """
  Changeset used to close an existing open assignment.
  """
  def close_changeset(%Assignment{} = assignment, attrs) do
    assignment
    |> cast(attrs, [:returned_on, :notes])
    |> validate_required([:returned_on])
    |> validate_returned_after_assigned()
    |> check_constraint(:returned_on,
      name: :asset_assignments_returned_after_assigned,
      message: "must be on or after the assignment date"
    )
  end

  defp validate_returned_after_assigned(changeset) do
    assigned_on = get_field(changeset, :assigned_on)
    returned_on = get_field(changeset, :returned_on)

    case {assigned_on, returned_on} do
      {%Date{} = a, %Date{} = r} ->
        if Date.before?(r, a) do
          add_error(changeset, :returned_on, "must be on or after the assignment date")
        else
          changeset
        end

      _other ->
        changeset
    end
  end
end
