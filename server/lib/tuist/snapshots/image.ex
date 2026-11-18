defmodule Tuist.Snapshots.Image do
  @moduledoc """
  An image of a snapshot build, identified within its set by `name` (its
  path relative to the uploaded directory, as Sentry and Roborazzi name
  them). The bytes live in object storage under their SHA-256
  (`content_hash`), so an image that didn't change since an earlier build is
  stored once.

  Processing fills the comparison with the baseline: `status` is
  `unchanged`, `changed`, `added`, `removed`, `renamed` or `skipped`. A
  removed image has no content of its own, only the baseline's. A renamed
  image is an added one with the content of a removed one (`renamed_from`),
  matched by content hash as Sentry does. A skipped image is one a selective
  run didn't render: it is created without content and processing carries
  the baseline's over, so the build stays a complete baseline for the next. An image whose pixels differ keeps
  the share that differ (`diff_ratio`) and the object key of a rendered diff;
  it is `changed` only when that share exceeds its `diff_threshold`, and
  `unchanged` otherwise.

  `display_name`, `group`, `tags` and `diff_threshold` come from the JSON
  file a client may upload beside each PNG, in the format Sentry Snapshots,
  tuist/snapshots and SnapshotPreviews write.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "snapshot_images" do
    field :name, :string
    field :content_hash, :string
    field :width, :integer
    field :height, :integer
    field :test_identifier, :string
    field :display_name, :string
    field :group, :string
    field :tags, :map, default: %{}
    field :diff_threshold, :float
    field :status, :string
    field :baseline_content_hash, :string
    field :baseline_width, :integer
    field :baseline_height, :integer
    field :diff_ratio, :float
    field :diff_key, :string
    field :renamed_from, :string
    # The build's set, when images of several builds are pooled (`Tuist.Snapshots.commit_images/2`).
    field :set_name, :string, virtual: true

    belongs_to :build, Tuist.Snapshots.Build

    timestamps(type: :utc_datetime)
  end

  def comparison_changeset(image, attrs) do
    cast(image, attrs, [
      :status,
      :baseline_content_hash,
      :baseline_width,
      :baseline_height,
      :diff_ratio,
      :diff_key,
      :renamed_from
    ])
  end
end
