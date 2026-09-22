defmodule AtlasWeb.NotesController do
  use AtlasWeb, :controller

  alias Atlas.Audit
  alias Atlas.MCP.Serializers.Notes, as: NoteSerializer
  alias Atlas.Notes
  alias Atlas.Notes.Note

  def index(conn, params) do
    {notes, meta} =
      Notes.list_notes_page(
        query: present(params["query"]),
        limit: normalize_limit(params["limit"]),
        offset: normalize_offset(params["offset"])
      )

    json(conn, %{
      notes: Enum.map(notes, &NoteSerializer.note/1),
      count: length(notes),
      pagination: %{
        total_count: meta.total_count,
        current_offset: meta.current_offset,
        page_size: meta.page_size,
        has_next_page?: meta.has_next_page?,
        has_previous_page?: meta.has_previous_page?
      }
    })
  end

  def create(conn, params) do
    result =
      Audit.with_context(%{actor: conn.assigns.current_user, interface: "api"}, fn ->
        Notes.create_note(Map.take(params, ["content", "visibility"]), conn.assigns.current_user)
      end)

    case result do
      {:ok, note} ->
        conn
        |> put_status(:created)
        |> json(%{note: NoteSerializer.note(note)})

      {:error, changeset} ->
        validation_error(conn, changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    case Notes.get_note(id) do
      %Note{} = note -> json(conn, %{note: NoteSerializer.note(note)})
      nil -> not_found(conn, "Note not found.")
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Notes.get_note(id) do
      %Note{} = note ->
        result =
          Audit.with_context(%{actor: conn.assigns.current_user, interface: "api"}, fn ->
            Notes.update_note(note, Map.take(params, ["content", "visibility"]))
          end)

        case result do
          {:ok, updated_note} -> json(conn, %{note: NoteSerializer.note(updated_note)})
          {:error, changeset} -> validation_error(conn, changeset)
        end

      nil ->
        not_found(conn, "Note not found.")
    end
  end

  def search(conn, %{"query" => query} = params) when is_binary(query) do
    results =
      Notes.search(query, limit: normalize_limit(params["limit"]))
      |> Enum.map(fn result ->
        %{note: NoteSerializer.note(result.note), excerpt: result.excerpt, score: result.score}
      end)

    json(conn, %{results: results, count: length(results)})
  end

  def search(conn, _params), do: json(conn, %{results: [], count: 0})

  defp not_found(conn, message) do
    conn |> put_status(:not_found) |> json(%{error: message})
  end

  defp validation_error(conn, %Ecto.Changeset{} = changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, &error_message/1)
    conn |> put_status(:unprocessable_entity) |> json(%{errors: errors})
  end

  defp error_message({message, options}) do
    Enum.reduce(options, message, fn {key, value}, message ->
      String.replace(message, "%{#{key}}", to_string(value))
    end)
  end

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp present(_value), do: nil

  defp normalize_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} -> limit
      _ -> nil
    end
  end

  defp normalize_limit(value), do: value

  defp normalize_offset(value) when is_binary(value) do
    case Integer.parse(value) do
      {offset, ""} -> offset
      _ -> 0
    end
  end

  defp normalize_offset(value), do: value
end
