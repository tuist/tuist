defmodule Atlas.Moodboard do
  @moduledoc "Shared references, articles, original text and discussion contributed by authenticated teammates."

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Moodboard.Comment
  alias Atlas.Moodboard.PreviewWorker
  alias Atlas.Moodboard.Resource
  alias Atlas.Repo
  alias Atlas.Search
  alias Atlas.Users.User

  def list_resources(%User{} = user, opts \\ []) do
    case Keyword.get(opts, :query) do
      query when is_binary(query) and query != "" -> search_resources(user, query, opts)
      _ -> list_recent_resources(opts)
    end
  end

  defp list_recent_resources(opts) do
    limit = normalize_limit(Keyword.get(opts, :limit, 24))
    offset = normalize_offset(Keyword.get(opts, :offset, 0))

    query =
      Resource
      |> filter_tag(Keyword.get(opts, :tag))
      |> order_by([resource], desc: resource.inserted_at, desc: resource.id)
      |> preload(:created_by)

    resources = query |> limit(^(limit + 1)) |> offset(^offset) |> Repo.all()
    {Enum.take(resources, limit), length(resources) > limit}
  end

  def get_resource(%User{}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(Resource, id) |> Repo.preload(:created_by)
      :error -> nil
    end
  end

  def create_resource(attrs, user, opts \\ [])

  def create_resource(attrs, %User{} = user, opts) do
    Repo.transaction(fn ->
      %Resource{created_by_id: user.id}
      |> Resource.changeset(attrs)
      |> prepare_preview()
      |> persist_resource(:insert, "moodboard_resource.created", user, opts)
    end)
  end

  def create_resource(_attrs, _user, _opts), do: {:error, :authentication_required}

  def capture_resource(request_id, attrs, user, opts \\ [])

  def capture_resource(request_id, attrs, %User{} = user, opts) when is_map(attrs) do
    with {:ok, request_id} <- Ecto.UUID.cast(request_id),
         true <- Enum.all?(Map.keys(attrs), &(&1 in ~w(title url content description tags image_url))) do
      # Serialize even the first insert. The actor-scoped request identity and hash
      # survive later resource edits, so a lost response cannot duplicate a text share.
      hash = :sha256 |> :crypto.hash(:erlang.term_to_binary(Enum.sort(attrs))) |> Base.encode16(case: :lower)

      Repo.transaction(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["moodboard:#{user.id}:#{request_id}"])

        case Repo.get_by(Resource, created_by_id: user.id, capture_id: request_id) do
          nil ->
            %Resource{created_by_id: user.id, capture_id: request_id, capture_hash: hash}
            |> Resource.changeset(attrs)
            |> prepare_preview()
            |> persist_resource(:insert, "moodboard_resource.created", user, opts)

          %Resource{capture_hash: ^hash} = resource ->
            Repo.preload(resource, :created_by)

          _ ->
            Repo.rollback(:capture_conflict)
        end
      end)
    else
      _ -> {:error, :invalid_capture}
    end
  end

  def capture_resource(_request_id, _attrs, _user, _opts), do: {:error, :authentication_required}

  def update_resource(id, attrs, user, opts \\ []) do
    mutate_owned_resource(id, user, fn resource ->
      resource
      |> Resource.changeset(attrs)
      |> prepare_preview()
      |> persist_resource(:update, "moodboard_resource.updated", user, opts)
    end)
  end

  def delete_resource(id, user, opts \\ []) do
    mutate_owned_resource(id, user, fn resource ->
      delete_resource_projection(resource)

      case Repo.delete(resource) do
        {:ok, deleted} -> record_result({:ok, deleted}, "moodboard_resource.deleted", user, opts) |> elem(1)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def change_resource(resource \\ %Resource{}, attrs \\ %{}), do: Resource.changeset(resource, attrs)

  def search_resources(%User{}, query, opts \\ []) do
    query = query |> String.trim() |> String.slice(0, 2000)
    if query == "", do: {[], false}, else: search_matching_resources(query, opts)
  end

  defp search_matching_resources(query, opts) do
    {:ok, hits} = Search.search(query, source_types: ["moodboard_resource", "moodboard_comment"], limit: 100)

    literal_ids =
      Resource
      |> filter_query(query)
      |> filter_tag(opts[:tag])
      |> order_by([r], desc: r.inserted_at, desc: r.id)
      |> limit(100)
      |> select([r], r.id)
      |> Repo.all()

    ids =
      hits
      |> Enum.map(fn hit ->
        if hit.source_type == "moodboard_comment", do: hit.metadata["resource_id"], else: hit.source_id
      end)
      |> then(&(literal_ids ++ &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.take(100)

    resources =
      Resource
      |> where([r], r.id in ^ids)
      |> filter_tag(opts[:tag])
      |> preload(:created_by)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    rows =
      ids |> Enum.map(&Map.get(resources, &1)) |> Enum.reject(&is_nil/1) |> Enum.drop(normalize_offset(opts[:offset]))

    limit = normalize_limit(opts[:limit])
    {Enum.take(rows, limit), length(rows) > limit}
  end

  def list_comments(%User{}, resource_id, opts \\ []) do
    limit = normalize_limit(Keyword.get(opts, :limit, 30))
    offset = normalize_offset(opts[:offset])

    if match?({:ok, _}, Ecto.UUID.cast(resource_id)) do
      rows =
        Comment
        |> where([c], c.resource_id == ^resource_id)
        |> order_by([c], asc: c.inserted_at, asc: c.id)
        |> limit(^(limit + 1))
        |> offset(^offset)
        |> preload(:author)
        |> Repo.all()

      {Enum.take(rows, limit), length(rows) > limit}
    else
      {[], false}
    end
  end

  def add_comment(resource_id, attrs, user, opts \\ [])

  def add_comment(resource_id, attrs, %User{} = user, opts) do
    case get_resource(user, resource_id) do
      nil ->
        {:error, :not_found}

      resource ->
        Repo.transaction(fn ->
          resource.id |> lock_resource!() |> insert_comment(attrs, user, opts)
        end)
    end
  end

  def add_comment(_resource_id, _attrs, _user, _opts), do: {:error, :authentication_required}

  def delete_comment(comment_id, user, opts \\ [])

  def delete_comment(comment_id, %User{} = user, opts) do
    comment = if match?({:ok, _}, Ecto.UUID.cast(comment_id)), do: Repo.get(Comment, comment_id)

    cond do
      is_nil(comment) ->
        {:error, :not_found}

      comment.author_id != user.id ->
        {:error, :forbidden}

      true ->
        Repo.transaction(fn ->
          lock_resource!(comment.resource_id)
          if is_nil(Repo.get(Comment, comment.id)), do: Repo.rollback(:not_found)
          Search.with_deferred_vectors(fn -> Search.delete_record("moodboard_comment", comment.id) end)

          case Repo.delete(comment) do
            {:ok, deleted} ->
              record_comment("moodboard_comment.deleted", deleted, user, opts)
              deleted

            {:error, reason} ->
              Repo.rollback(reason)
          end
        end)
    end
  end

  def delete_comment(_comment_id, _user, _opts), do: {:error, :authentication_required}

  def refresh_preview(id, user, opts \\ []) do
    mutate_owned_resource(id, user, fn resource ->
      if recent_preview_pending?(resource) do
        Repo.preload(resource, :created_by)
      else
        resource
        |> Resource.changeset(%{})
        |> Ecto.Changeset.force_change(:url, resource.url)
        |> prepare_preview()
        |> persist_resource(:update, "moodboard_resource.preview_requested", user, opts)
      end
    end)
  end

  def last_comment_offset(%User{}, resource_id, page_size \\ 30) do
    count = Repo.aggregate(from(c in Comment, where: c.resource_id == ^resource_id), :count)
    div(max(count - 1, 0), normalize_limit(page_size)) * normalize_limit(page_size)
  end

  defp recent_preview_pending?(resource) do
    resource.preview_status == "pending" and not is_nil(resource.preview_revision) and
      DateTime.diff(DateTime.utc_now(), resource.updated_at) < 120
  end

  def apply_preview(id, revision, result) do
    Repo.transaction(fn ->
      resource = Repo.one(from r in Resource, where: r.id == ^id, lock: "FOR UPDATE")

      if resource && resource.preview_revision == revision && resource.preview_status == "pending" do
        attrs =
          case result do
            {:ok, attrs} ->
              Map.merge(attrs, %{
                preview_status: "ready",
                preview_fetched_at: DateTime.utc_now() |> DateTime.truncate(:second)
              })

            _ ->
              %{preview_status: "unavailable"}
          end

        updated = persist_preview(resource, attrs)
        Search.with_deferred_vectors(fn -> {:ok, _} = Search.index_moodboard_resource(updated) end)
      end

      :ok
    end)
  end

  defp persist_preview(resource, attrs) do
    resource
    |> Resource.preview_changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} -> updated
      {:error, _changeset} -> resource |> Ecto.Changeset.change(preview_status: "unavailable") |> Repo.update!()
    end
  end

  defp prepare_preview(changeset) do
    if changeset.data.__meta__.state == :built or Map.has_key?(changeset.changes, :url) do
      url = Ecto.Changeset.get_field(changeset, :url)

      Ecto.Changeset.change(changeset, %{
        kind: if(url, do: "link", else: "text"),
        preview_status: if(url, do: "pending", else: "ready"),
        preview_revision: Ecto.UUID.generate(),
        preview_fetched_at: nil,
        source_title: nil,
        source_description: nil,
        source_text: nil,
        preview_image_url: nil,
        preview_video_url: nil
      })
    else
      changeset
    end
  end

  defp persist_resource(changeset, operation, action, user, opts) do
    case apply(Repo, operation, [changeset]) do
      {:ok, resource} ->
        index_resource(resource, Map.has_key?(changeset.changes, :title) and operation == :update)

        if resource.url && Map.has_key?(changeset.changes, :preview_revision) do
          %{resource_id: resource.id, revision: resource.preview_revision} |> PreviewWorker.new() |> Oban.insert!()
        end

        record_result({:ok, resource}, action, user, opts) |> elem(1)

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp mutate_owned_resource(id, user, fun) do
    with {:ok, resource} <- owned_resource(user, id) do
      Repo.transaction(fn ->
        resource = lock_resource!(resource.id)
        if resource.created_by_id != user.id, do: Repo.rollback(:forbidden)
        fun.(resource)
      end)
    end
  end

  defp insert_comment(resource, attrs, user, opts) do
    %Comment{resource_id: resource.id, author_id: user.id}
    |> Comment.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, comment} ->
        Search.with_deferred_vectors(fn -> {:ok, _} = Search.index_moodboard_comment(comment, resource) end)
        record_comment("moodboard_comment.created", comment, user, opts)
        Repo.preload(comment, :author)

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp index_resource(resource, title_changed?) do
    Search.with_deferred_vectors(fn ->
      {:ok, _} = Search.index_moodboard_resource(resource)
      if title_changed?, do: reindex_comments(resource)
    end)
  end

  defp reindex_comments(resource) do
    for comment <- Repo.all(from c in Comment, where: c.resource_id == ^resource.id) do
      {:ok, _} = Search.index_moodboard_comment(comment, resource)
    end
  end

  defp delete_resource_projection(resource) do
    Search.with_deferred_vectors(fn ->
      for comment <- Repo.all(from c in Comment, where: c.resource_id == ^resource.id) do
        Search.delete_record("moodboard_comment", comment.id)
      end

      Search.delete_record("moodboard_resource", resource.id)
    end)
  end

  defp lock_resource!(id) do
    case Repo.one(from r in Resource, where: r.id == ^id, lock: "FOR UPDATE") do
      nil -> Repo.rollback(:not_found)
      resource -> resource
    end
  end

  defp record_comment(action, comment, user, opts) do
    Audit.with_context(%{actor: user, interface: Keyword.get(opts, :interface, "mcp")}, fn ->
      Audit.record(action, %{
        target_type: "moodboard_comment",
        target_id: comment.id,
        metadata: %{"resource_id" => comment.resource_id, "path" => "/library/moodboard/#{comment.resource_id}"}
      })
    end)
  end

  defp owned_resource(%User{} = user, id) do
    case get_resource(user, id) do
      nil -> {:error, :not_found}
      %Resource{created_by_id: owner_id} = resource when owner_id == user.id -> {:ok, resource}
      _ -> {:error, :forbidden}
    end
  end

  defp owned_resource(_user, _id), do: {:error, :authentication_required}

  defp record_result({:ok, resource}, action, user, opts) do
    Audit.with_context(%{actor: user, interface: Keyword.get(opts, :interface, "mcp")}, fn ->
      Audit.record(action, %{
        target_type: "moodboard_resource",
        target_id: resource.id,
        target_label: resource.title,
        metadata: %{
          "path" =>
            if(action == "moodboard_resource.deleted",
              do: "/library/moodboard",
              else: "/library/moodboard/#{resource.id}"
            )
        }
      })
    end)

    {:ok, Repo.preload(resource, :created_by)}
  end

  defp filter_query(query, value) when is_binary(value) and value != "" do
    pattern = "%" <> escape_like(String.trim(value)) <> "%"

    comments = from c in Comment, where: ilike(c.body, ^pattern), select: c.resource_id

    where(
      query,
      [resource],
      ilike(resource.title, ^pattern) or ilike(resource.description, ^pattern) or
        ilike(resource.url, ^pattern) or ilike(resource.content, ^pattern) or
        ilike(resource.source_text, ^pattern) or ilike(resource.source_description, ^pattern) or
        ilike(fragment("array_to_string(?, ' ')", resource.tags), ^pattern) or resource.id in subquery(comments)
    )
  end

  defp filter_query(query, _value), do: query

  defp filter_tag(query, tag) when is_binary(tag) and tag != "" do
    tag = tag |> String.trim() |> String.downcase()
    where(query, [resource], ^tag in resource.tags)
  end

  defp filter_tag(query, _tag), do: query

  defp escape_like(value) do
    value |> String.replace("\\", "\\\\") |> String.replace("%", "\\%") |> String.replace("_", "\\_")
  end

  defp normalize_limit(value) when is_integer(value) and value > 0, do: min(value, 100)
  defp normalize_limit(_value), do: 24
  defp normalize_offset(value) when is_integer(value) and value >= 0, do: value
  defp normalize_offset(_value), do: 0
end
