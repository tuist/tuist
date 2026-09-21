defmodule Atlas.Engineering.Pages.Page do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Atlas.Engineering.Pages.Deploy
  alias Atlas.Engineering.Pages.ReservedSlugs
  alias Atlas.Users.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @slug_regex ~r/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/

  schema "pages" do
    field :slug, :string
    field :title, :string
    field :description, :string

    belongs_to :created_by_user, User
    belongs_to :current_deploy, Deploy

    has_many :deploys, Deploy

    timestamps(type: :utc_datetime)
  end

  def slug_regex, do: @slug_regex

  def changeset(page, attrs) do
    page
    |> cast(attrs, [:slug, :title, :description, :created_by_user_id, :current_deploy_id])
    |> update_change(:slug, &normalize_slug/1)
    |> validate_required([:slug])
    |> validate_length(:slug, min: 1, max: 63)
    |> validate_format(:slug, @slug_regex,
      message: "must be lowercase letters, digits, and hyphens; must not start or end with a hyphen"
    )
    |> validate_not_reserved()
    |> validate_length(:title, max: 160)
    |> validate_length(:description, max: 280)
    |> unique_constraint(:slug)
  end

  defp normalize_slug(nil), do: nil
  defp normalize_slug(value) when is_binary(value), do: value |> String.trim() |> String.downcase()
  defp normalize_slug(other), do: other

  defp validate_not_reserved(changeset) do
    validate_change(changeset, :slug, fn :slug, value ->
      if ReservedSlugs.reserved?(value) do
        [slug: "is reserved for the platform"]
      else
        []
      end
    end)
  end
end
