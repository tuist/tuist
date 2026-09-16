defmodule Atlas.Notes do
  @moduledoc """
  Markdown notes shared by the dashboard, API, and MCP clients.

  A note's title is always derived from its first level-one Markdown heading.
  Notes are currently visible to every authenticated user. The visibility field
  and this context boundary leave room for replacing that rule with a policy
  without changing the clients.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Notes.Note
  alias Atlas.Repo
  alias Atlas.Search
  alias Atlas.Users.User

  @default_limit 25
  @max_limit 100

  def list_notes(opts \\ []) do
    limit = normalize_limit(Keyword.get(opts, :limit, @default_limit))

    Note
    |> maybe_filter_query(Keyword.get(opts, :query))
    |> maybe_filter(:created_by_id, Keyword.get(opts, :created_by_id))
    |> order_by([note], desc: note.updated_at, desc: note.id)
    |> limit(^limit)
    |> preload(:created_by)
    |> Repo.all()
  end

  @doc "Lists notes with Flop metadata for HTTP API pagination."
  def list_notes_page(opts \\ []) do
    limit = normalize_limit(Keyword.get(opts, :limit, @default_limit))
    offset = opts |> Keyword.get(:offset, 0) |> normalize_offset()

    query =
      Note
      |> maybe_filter_query(Keyword.get(opts, :query))
      |> maybe_filter(:created_by_id, Keyword.get(opts, :created_by_id))
      |> preload(:created_by)

    {notes, meta} = Flop.run(query, %Flop{limit: limit, offset: offset}, for: Note)
    {notes, meta}
  end

  def get_note(id) when is_binary(id) do
    Note
    |> Repo.get(id)
    |> preload_note()
  end

  def create_note(attrs, user, opts \\ [])

  def create_note(attrs, %User{} = user, opts) when is_map(attrs) do
    %Note{created_by_id: user.id}
    |> Note.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, note} ->
        note = index_note(note)
        audit_note("note.created", note, opts, user)
        {:ok, note}

      {:error, _changeset} = error ->
        error
    end
  end

  def create_note(_attrs, _user, _opts), do: {:error, :authentication_required}

  def update_note(%Note{} = note, attrs, opts \\ []) when is_map(attrs) do
    changeset = Note.changeset(note, attrs)

    case Repo.update(changeset) do
      {:ok, updated_note} ->
        updated_note = index_note(updated_note)
        audit_note("note.updated", updated_note, opts, Keyword.get(opts, :audit_actor))
        {:ok, updated_note}

      {:error, _changeset} = error ->
        error
    end
  end

  def delete_note(%Note{} = note, opts \\ []) do
    case Repo.delete(note) do
      {:ok, deleted_note} ->
        _ = Search.delete_record("note", deleted_note.id)
        audit_note("note.deleted", deleted_note, opts, Keyword.get(opts, :audit_actor))
        {:ok, deleted_note}

      {:error, _changeset} = error ->
        error
    end
  end

  @doc "Searches note titles and Markdown content using lexical and vector search."
  def search(query, opts \\ [])

  def search(query, opts) when is_binary(query) do
    opts =
      opts
      |> Keyword.put(:source_types, ["note"])
      |> Keyword.put(:qmd_mode, true)
      |> Keyword.update(:limit, @default_limit, &normalize_limit/1)

    {:ok, results} = Search.search(query, opts)

    results
    |> Enum.map(fn result ->
      case get_note(result.source_id) do
        %Note{} = note -> Map.put(result, :note, note)
        nil -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  def search(_query, _opts), do: []

  def change_note(%Note{} = note, attrs \\ %{}), do: Note.changeset(note, attrs)

  defp index_note(note) do
    case Search.index_note(note) do
      {:ok, _record} -> get_note(note.id)
      {:error, _reason} -> get_note(note.id)
    end
  end

  defp preload_note(nil), do: nil
  defp preload_note(%Note{} = note), do: Repo.preload(note, :created_by)

  defp maybe_filter_query(query, nil), do: query
  defp maybe_filter_query(query, ""), do: query

  defp maybe_filter_query(query, value) when is_binary(value) do
    like = "%#{String.replace(value, "%", "\\%")}%"
    where(query, [note], ilike(note.title, ^like) or ilike(note.content, ^like))
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, _field, ""), do: query
  defp maybe_filter(query, field, value), do: where(query, [note], field(note, ^field) == ^value)

  defp normalize_limit(limit) when is_integer(limit) and limit > 0, do: min(limit, @max_limit)
  defp normalize_limit(_limit), do: @default_limit

  defp normalize_offset(offset) when is_integer(offset) and offset >= 0, do: offset
  defp normalize_offset(_offset), do: 0

  defp audit_note(action, note, opts, actor) do
    context =
      opts
      |> Keyword.take([:interface, :audit_actor])
      |> Keyword.put_new(:actor, actor)
      |> Keyword.put_new(:metadata, %{"path" => "/notes/#{note.id}"})

    Audit.with_context(context, fn ->
      Audit.record(action, %{
        target_type: "note",
        target_id: note.id,
        target_label: note.title,
        metadata: %{"path" => "/notes/#{note.id}"}
      })
    end)
  end
end
