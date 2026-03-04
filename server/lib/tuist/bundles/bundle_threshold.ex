defmodule Tuist.Bundles.BundleThreshold do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "bundle_thresholds" do
    field :name, :string, default: "Untitled"

    field :metric, Ecto.Enum,
      values: [
        install_size: 0,
        download_size: 1
      ]

    field :deviation_percentage, :float
    field :baseline_branch, :string
    field :bundle_name, :string

    belongs_to :project, Tuist.Projects.Project, type: :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(threshold, attrs) do
    threshold
    |> cast(attrs, [:id, :name, :metric, :deviation_percentage, :baseline_branch, :bundle_name, :project_id])
    |> validate_required([:name, :metric, :deviation_percentage, :baseline_branch, :project_id])
    |> validate_number(:deviation_percentage, greater_than: 0)
    |> foreign_key_constraint(:project_id)
  end
end
