defmodule Tuist.Runners.RunnerImage do
  @moduledoc """
  Represents golden VM images for Tuist Runners.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "runner_images" do
    field :name, :string
    field :os_version, :string
    field :xcode_version, :string
    field :base_image_name, :string
    field :labels, {:array, :string}
    field :status, Ecto.Enum, values: [active: 0, deprecated: 1, building: 2, failed: 3]
    field :size_gb, :integer
    field :checksum, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(runner_image, attrs) do
    runner_image
    |> cast(attrs, [
      :id,
      :name,
      :os_version,
      :xcode_version,
      :base_image_name,
      :labels,
      :status,
      :size_gb,
      :checksum
    ])
    |> validate_required([
      :id,
      :name,
      :os_version,
      :xcode_version,
      :status
    ])
    |> validate_number(:size_gb, greater_than: 0)
    |> validate_format(:checksum, ~r/^[a-f0-9]{64}$/i)
    |> unique_constraint(:name)
  end

  def active_query do
    from image in __MODULE__, where: image.status == :active
  end

  def by_labels_query(labels) do
    from image in active_query(),
      where: fragment("? && ?", image.labels, ^labels)
  end

  def by_xcode_version_query(version) do
    from image in active_query(), where: image.xcode_version == ^version
  end

  def by_os_version_query(version) do
    from image in active_query(), where: image.os_version == ^version
  end
end
