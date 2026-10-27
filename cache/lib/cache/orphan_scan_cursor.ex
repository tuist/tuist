defmodule Cache.OrphanScanCursor do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "orphan_scan_cursors" do
    field :cursor_path, :string
    field :last_completed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(cursor, attrs) do
    cast(cursor, attrs, [:cursor_path, :last_completed_at])
  end
end
