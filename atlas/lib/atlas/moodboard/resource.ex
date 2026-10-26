defmodule Atlas.Moodboard.Resource do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Moodboard.Text
  alias Atlas.URL
  alias Atlas.Users.User

  schema "moodboard_resources" do
    field :title, :string
    field :url, :string
    field :description, :string
    field :image_url, :string
    field :content, :string
    field :kind, :string, default: "link"
    field :source_title, :string
    field :source_description, :string
    field :source_text, :string
    field :preview_image_url, :string
    field :preview_video_url, :string
    field :preview_status, :string, default: "pending"
    field :preview_revision, Ecto.UUID
    field :preview_fetched_at, :utc_datetime
    field :tags, {:array, :string}, default: []
    belongs_to :created_by, User

    timestamps(type: :utc_datetime)
  end

  def changeset(resource, attrs) do
    resource
    |> cast(attrs, [:title, :url, :description, :image_url, :content, :tags])
    |> trim_fields()
    |> validate_text()
    |> update_change(:tags, &normalize_tags/1)
    |> validate_required([:title])
    |> validate_resource_content()
    |> validate_length(:title, max: 200)
    |> validate_length(:description, max: 2000)
    |> validate_length(:content, max: 20_000)
    |> validate_length(:url, max: 2048)
    |> validate_length(:image_url, max: 2048)
    |> validate_length(:tags, max: 10)
    |> validate_change(:tags, fn :tags, tags ->
      cond do
        Enum.any?(tags, &(not Text.valid?(&1))) -> [tags: "must be valid text without null bytes"]
        Enum.any?(tags, &(String.length(&1) > 40)) -> [tags: "must be at most 40 characters each"]
        true -> []
      end
    end)
    |> validate_url(:url)
    |> validate_url(:image_url)
    |> unique_constraint(:url)
    |> assoc_constraint(:created_by)
  end

  def preview_changeset(resource, attrs) do
    resource
    |> cast(attrs, [
      :kind,
      :source_title,
      :source_description,
      :source_text,
      :preview_image_url,
      :preview_video_url,
      :preview_status,
      :preview_fetched_at
    ])
    |> update_change(:source_title, &Text.clean(&1, 200))
    |> update_change(:source_description, &Text.clean(&1, 2000))
    |> update_change(:source_text, &Text.clean(&1, 20_000))
    |> validate_inclusion(:kind, ~w(link article image video text))
    |> validate_length(:preview_image_url, max: 2048)
    |> validate_length(:preview_video_url, max: 2048)
    |> validate_url(:preview_image_url)
    |> validate_url(:preview_video_url)
  end

  defp validate_text(changeset) do
    Enum.reduce([:title, :url, :description, :image_url, :content], changeset, fn field, acc ->
      validate_change(acc, field, fn ^field, value ->
        if Text.valid?(value), do: [], else: [{field, "must be valid text without null bytes"}]
      end)
    end)
  end

  defp validate_resource_content(changeset) do
    if get_field(changeset, :url) in [nil, ""] do
      changeset
      |> validate_required([:content])
      |> put_change(:kind, "text")
      |> then(fn changeset ->
        if get_field(changeset, :content) in [nil, ""], do: validate_required(changeset, [:url]), else: changeset
      end)
    else
      if get_field(changeset, :kind) == "text", do: put_change(changeset, :kind, "link"), else: changeset
    end
  end

  defp trim_fields(changeset) do
    Enum.reduce([:title, :url, :description, :image_url, :content], changeset, fn field, acc ->
      update_change(acc, field, fn
        value when is_binary(value) -> String.trim(value)
        value -> value
      end)
    end)
  end

  defp normalize_tags(nil), do: []

  defp normalize_tags(tags) do
    tags
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn tag -> tag |> String.trim() |> String.downcase() end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      with {:ok, _uri} <- URI.new(value),
           {:ok, %{scheme: "https"}} <- URL.validate_public(value) do
        []
      else
        _ -> [{field, "must be a public HTTPS URL"}]
      end
    end)
  end
end
