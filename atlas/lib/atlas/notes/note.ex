defmodule Atlas.Notes.Note do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Users.User

  @visibilities ~w(authenticated)

  @derive {
    Flop.Schema,
    filterable: [],
    sortable: [:inserted_at, :updated_at],
    default_order: %{order_by: [:updated_at], order_directions: [:desc]},
    default_limit: 25,
    max_limit: 100
  }

  schema "notes" do
    field :title, :string
    field :content, :string
    field :visibility, :string, default: "authenticated"

    belongs_to :created_by, User

    timestamps()
  end

  @doc "Builds a note changeset and derives its title from the first level-one heading."
  def changeset(note, attrs) do
    changeset =
      note
      |> cast(attrs, [:content, :visibility])
      |> normalize_content()
      |> put_derived_title()
      |> validate_required([:title, :content, :visibility])
      |> validate_inclusion(:visibility, @visibilities)
      |> assoc_constraint(:created_by)

    if get_field(changeset, :title) do
      changeset
    else
      add_error(changeset, :content, "must start with an h1 heading")
    end
  end

  def title_from_content(content) when is_binary(content) do
    lines = String.split(content, "\n")

    lines
    |> Enum.with_index()
    |> Enum.find_value(fn {line, index} ->
      title_from_line(line) || setext_title(lines, line, index)
    end)
  end

  def title_from_content(_content), do: nil

  def visibilities, do: @visibilities

  defp normalize_content(changeset) do
    update_change(changeset, :content, fn content -> String.trim(content) end)
  end

  defp put_derived_title(changeset) do
    case get_change(changeset, :content) do
      content when is_binary(content) -> put_change(changeset, :title, title_from_content(content))
      _content -> changeset
    end
  end

  defp title_from_line(line) do
    case Regex.run(~r/^\s{0,3}#\s+(.+?)\s*#*\s*$/, line, capture: :all_but_first) do
      [title] -> normalize_title(title)
      _ -> nil
    end
  end

  defp setext_title(lines, line, index) do
    if Regex.match?(~r/^\s*=+\s*$/, Enum.at(lines, index + 1, "")) do
      normalize_title(line)
    end
  end

  defp normalize_title(title) do
    case String.trim(title) do
      "" -> nil
      title -> title
    end
  end
end
