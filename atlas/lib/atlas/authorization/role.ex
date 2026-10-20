defmodule Atlas.Authorization.Role do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Authorization
  alias Atlas.Authorization.UserRole
  alias Atlas.Users.User

  schema "roles" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :scopes, {:array, :string}, default: []
    field :builtin, :boolean, default: false

    many_to_many :users, User, join_through: UserRole, unique: true

    timestamps(type: :utc_datetime)
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :slug, :description, :scopes, :builtin])
    |> update_change(:slug, &slugify/1)
    |> validate_required([:name, :slug])
    |> validate_length(:name, max: 120)
    |> validate_length(:slug, max: 60)
    |> validate_format(:slug, ~r/^[a-z][a-z0-9_-]*$/,
      message: "must be lowercase letters, digits, dashes, or underscores"
    )
    |> update_change(:scopes, &normalize_scopes/1)
    |> validate_scopes()
    |> unique_constraint(:slug)
  end

  defp slugify(nil), do: nil
  defp slugify(slug) when is_binary(slug), do: slug |> String.downcase() |> String.trim()

  defp normalize_scopes(nil), do: []

  defp normalize_scopes(scopes) when is_list(scopes) do
    scopes
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp validate_scopes(changeset) do
    validate_change(changeset, :scopes, fn :scopes, scopes ->
      case Enum.reject(scopes, &match?({:ok, _, _}, Authorization.parse(&1))) do
        [] -> []
        invalid -> [scopes: "unknown scopes: #{Enum.join(invalid, ", ")}"]
      end
    end)
  end
end
