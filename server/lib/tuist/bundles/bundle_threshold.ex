defmodule Tuist.Bundles.BundleThreshold do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "bundle_thresholds" do
    field :name, :string

    field :metric, Ecto.Enum,
      values: [
        install_size: 0,
        download_size: 1
      ]

    field :deviation_percentage, :float
    field :deviation_bytes, :integer
    field :baseline_branch, :string
    field :bundle_name, :string

    belongs_to :project, Tuist.Projects.Project, type: :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(threshold, attrs) do
    threshold
    |> cast(attrs, [
      :id,
      :name,
      :metric,
      :deviation_percentage,
      :deviation_bytes,
      :baseline_branch,
      :bundle_name,
      :project_id
    ])
    |> validate_required([:name, :metric, :baseline_branch, :project_id])
    |> validate_limit()
    |> validate_number(:deviation_percentage, greater_than: 0)
    |> validate_number(:deviation_bytes, greater_than: 0, less_than_or_equal_to: 9_223_372_036_854_775_807)
    |> check_constraint(:deviation_bytes, name: :bundle_thresholds_one_limit)
    |> foreign_key_constraint(:project_id)
  end

  def limit_label(%{deviation_bytes: bytes}) when is_integer(bytes), do: "#{megabytes(bytes)} MB"
  def limit_label(%{deviation_percentage: percentage}), do: "#{percentage}%"

  def megabytes(bytes) do
    bytes |> Decimal.new() |> Decimal.div(1_000_000) |> Decimal.normalize() |> Decimal.to_string(:normal)
  end

  defp validate_limit(changeset) do
    case {get_field(changeset, :deviation_percentage), get_field(changeset, :deviation_bytes)} do
      {nil, nil} ->
        add_error(changeset, :deviation_percentage, "can't be blank")

      {percentage, bytes} when not is_nil(percentage) and not is_nil(bytes) ->
        add_error(changeset, :deviation_bytes, "must not be set with a percentage")

      _ ->
        changeset
    end
  end
end
