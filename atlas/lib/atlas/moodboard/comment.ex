defmodule Atlas.Moodboard.Comment do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Moodboard.Resource
  alias Atlas.Moodboard.Text
  alias Atlas.Users.User

  schema "moodboard_comments" do
    field :body, :string
    belongs_to :resource, Resource
    belongs_to :author, User
    timestamps(type: :utc_datetime)
  end

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:body])
    |> update_change(:body, fn value -> if is_binary(value), do: String.trim(value), else: value end)
    |> validate_required([:body])
    |> validate_length(:body, max: 4000)
    |> validate_change(:body, fn :body, value ->
      if Text.valid?(value), do: [], else: [body: "must be valid text without null bytes"]
    end)
    |> assoc_constraint(:resource)
    |> assoc_constraint(:author)
  end
end
