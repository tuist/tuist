defmodule Cache.OrphanScanCursor do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Cache.Repo

  schema "orphan_scan_cursors" do
    field :cursor_path, :string
    field :last_completed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(cursor, attrs) do
    cast(cursor, attrs, [:cursor_path, :last_completed_at])
  end

  def get_cursor do
    __MODULE__
    |> first()
    |> Repo.one()
  end

  def update_cursor(cursor_path) do
    case get_cursor() do
      nil ->
        %__MODULE__{}
        |> changeset(%{cursor_path: cursor_path})
        |> Repo.insert!()

      existing ->
        existing
        |> changeset(%{cursor_path: cursor_path})
        |> Repo.update!()
    end

    :ok
  end

  def reset_cursor do
    case get_cursor() do
      nil ->
        %__MODULE__{}
        |> changeset(%{cursor_path: nil, last_completed_at: DateTime.utc_now()})
        |> Repo.insert!()

      existing ->
        existing
        |> changeset(%{cursor_path: nil, last_completed_at: DateTime.utc_now()})
        |> Repo.update!()
    end

    :ok
  end
end
