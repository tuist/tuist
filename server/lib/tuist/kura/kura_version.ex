defmodule Tuist.Kura.KuraVersion do
  @moduledoc """
  A published Kura release as seen by the version poller. The poller
  populates this table from the public GitHub Releases feed of the
  monorepo, filtering for tags matching `kura@<semver>`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "kura_versions" do
    field :version, :string
    field :released_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(version \\ %__MODULE__{}, attrs) do
    version
    |> cast(attrs, [:version, :released_at])
    |> validate_required([:version, :released_at])
    |> validate_format(:version, ~r/^\d+\.\d+\.\d+$/, message: "must be a semantic version like 0.5.2")
    |> unique_constraint(:version)
  end
end
