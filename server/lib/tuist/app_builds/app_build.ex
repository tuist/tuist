defmodule Tuist.AppBuilds.AppBuild do
  @moduledoc """
  A module that represents a single preview bundle.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.AppBuilds.Preview

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "app_builds" do
    belongs_to :preview, Preview, type: UUIDv7

    field :type, Ecto.Enum,
      values: [
        app_bundle: 0,
        ipa: 1
      ]

    field :supported_platforms, {:array, Ecto.Enum},
      values: [
        ios: 0,
        ios_simulator: 1,
        tvos: 2,
        tvos_simulator: 3,
        watchos: 4,
        watchos_simulator: 5,
        visionos: 6,
        visionos_simulator: 7,
        macos: 8
      ]

    field :binary_id, :string
    field :build_version, :string

    timestamps(type: :utc_datetime)
  end

  def create_changeset(token, attrs) do
    token
    |> cast(attrs, [
      :preview_id,
      :type,
      :inserted_at,
      :supported_platforms,
      :binary_id,
      :build_version
    ])
    |> validate_subset(:supported_platforms, Ecto.Enum.values(__MODULE__, :supported_platforms))
    |> validate_required([:preview_id, :type])
    |> unique_constraint([:binary_id, :build_version])
  end
end
