defmodule Atlas.GTM.SocialMedia do
  @moduledoc """
  An image or video for a social post. Its bytes live in the documents bucket
  under `social-media/`; X receives them only when the post publishes.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Users.User

  @image_types ~w(image/jpeg image/png image/webp)
  @gif_types ~w(image/gif)
  @video_types ~w(video/mp4 video/quicktime)

  # X's own limits: 5 MB for an image and 15 MB for a GIF. Videos are capped
  # lower than X allows because Atlas reads the whole file to upload it.
  @max_bytes %{"image" => 5_000_000, "gif" => 15_000_000, "video" => 100_000_000}

  def content_types, do: @image_types ++ @gif_types ++ @video_types
  def max_bytes(kind), do: Map.fetch!(@max_bytes, kind)

  def kind(%__MODULE__{content_type: type}), do: kind(type)
  def kind(type) when type in @image_types, do: "image"
  def kind(type) when type in @gif_types, do: "gif"
  def kind(type) when type in @video_types, do: "video"

  schema "social_media" do
    field :filename, :string
    field :content_type, :string
    field :byte_size, :integer
    field :storage_key, :string
    field :status, :string, default: "pending_upload"

    belongs_to :uploaded_by, User

    timestamps(type: :utc_datetime)
  end

  def changeset(media, attrs) do
    media
    |> cast(attrs, [:filename, :content_type, :byte_size, :storage_key, :status])
    |> validate_required([:filename, :content_type, :storage_key, :status])
    |> validate_length(:filename, max: 255)
    |> validate_inclusion(:content_type, content_types())
    |> validate_inclusion(:status, ~w(pending_upload uploaded))
  end
end
