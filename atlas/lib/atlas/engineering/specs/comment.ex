defmodule Atlas.Engineering.Specs.Comment do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Atlas.Engineering.Specs.Spec
  alias Atlas.Users.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "spec_comments" do
    field :body, :string
    field :author_name, :string

    belongs_to :spec, Spec
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:body, :author_name])
    |> update_change(:author_name, &normalize_author_name/1)
    |> validate_required([:body])
    |> validate_length(:body, min: 2, max: 20_000)
    |> validate_length(:author_name, max: 160)
    |> foreign_key_constraint(:spec_id)
  end

  defp normalize_author_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_author_name(name), do: name
end
