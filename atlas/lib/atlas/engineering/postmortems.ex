defmodule Atlas.Engineering.Postmortems do
  @moduledoc """
  Incident postmortems published by Atlas operators.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Engineering.Domains.Domain
  alias Atlas.Engineering.Postmortems.ActionItem
  alias Atlas.Engineering.Postmortems.Embedding
  alias Atlas.Engineering.Postmortems.EmbeddingWorker
  alias Atlas.Engineering.Postmortems.Postmortem
  alias Atlas.Repo
  alias Atlas.Users.User
  alias AtlasWeb.Markdown
  alias Ecto.Changeset

  @embedding_input_limit 24_000

  # Atlas has no per-user gating like Hive's Auth.member?: any authenticated
  # user is a member of the operator team, so publish/edit/delete are gated
  # only on the presence of a %User{}.
  def can_publish?(%User{}), do: true
  def can_publish?(_user), do: false

  def can_edit?(%Postmortem{}, %User{}), do: true
  def can_edit?(_postmortem, _user), do: false

  def can_delete?(%Postmortem{} = postmortem, user), do: can_edit?(postmortem, user)

  def can_view?(%Postmortem{}, %User{}), do: true
  def can_view?(%Postmortem{}, _user), do: false

  def list_postmortems(_user \\ nil) do
    Postmortem
    |> order_by([postmortem], desc: postmortem.inserted_at)
    |> preload([:created_by_user, :domains, action_items: ^action_items_query()])
    |> Repo.all()
  end

  def list_postmortems_page(opts \\ []) do
    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = Keyword.get(opts, :page_size, 20)

    query =
      Postmortem
      |> maybe_search(Keyword.get(opts, :query))
      |> maybe_filter_published(Keyword.get(opts, :published))

    total_entries = Repo.aggregate(query, :count)
    total_pages = max(ceil(total_entries / page_size), 1)
    page = min(page, total_pages)

    postmortems =
      query
      |> order_by([postmortem], desc: postmortem.inserted_at)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> preload([:created_by_user, :domains, action_items: ^action_items_query()])
      |> Repo.all()

    {postmortems, %{current_page: page, total_pages: total_pages, total_entries: total_entries}}
  end

  def get_postmortem!(id) do
    Postmortem
    |> preload_postmortem()
    |> Repo.get!(id)
  end

  def get_postmortem(id) do
    Postmortem
    |> preload_postmortem()
    |> Repo.get(id)
  end

  def get_postmortem_by_number!(number), do: Postmortem |> preload_postmortem() |> Repo.get_by!(number: number)

  def get_postmortem_by_number(number), do: Postmortem |> preload_postmortem() |> Repo.get_by(number: number)

  def get_postmortem_by_share_token(nil), do: nil

  def get_postmortem_by_share_token(token) when is_binary(token) do
    Postmortem |> preload_postmortem() |> Repo.get_by(share_token: token)
  rescue
    Ecto.Query.CastError -> nil
  end

  def ensure_share_token(%Postmortem{share_token: token} = postmortem) when is_binary(token), do: {:ok, postmortem}

  def ensure_share_token(%Postmortem{} = postmortem) do
    postmortem
    |> Postmortem.share_token_changeset(Ecto.UUID.generate())
    |> Repo.update()
  end

  def get_postmortem_by_reference(reference) when is_integer(reference), do: get_postmortem_by_number(reference)

  def get_postmortem_by_reference(reference) when is_binary(reference) do
    reference
    |> reference_identifier()
    |> case do
      "" ->
        nil

      identifier ->
        if public_number?(identifier),
          do: get_postmortem_by_number(identifier),
          else: get_postmortem(identifier)
    end
  rescue
    Ecto.Query.CastError -> nil
  end

  def fetch_visible_postmortem_by_number(number, user) do
    case get_postmortem_by_number(number) do
      %Postmortem{} = postmortem ->
        if(can_view?(postmortem, user), do: {:ok, postmortem}, else: {:error, :not_found})

      _ ->
        {:error, :not_found}
    end
  end

  def fetch_visible_postmortem_by_reference(reference, user) do
    case get_postmortem_by_reference(reference) do
      %Postmortem{} = postmortem ->
        if(can_view?(postmortem, user), do: {:ok, postmortem}, else: {:error, :not_found})

      _ ->
        {:error, :not_found}
    end
  end

  def fetch_visible_action_item(id, user) when is_binary(id) do
    with %ActionItem{} = action_item <- Repo.get(ActionItem, id),
         %Postmortem{} = postmortem <- get_postmortem(action_item.postmortem_id),
         true <- can_view?(postmortem, user) do
      {:ok, postmortem, action_item}
    else
      _ -> {:error, :not_found}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def change_postmortem(postmortem \\ %Postmortem{}, attrs \\ %{}), do: Postmortem.changeset(postmortem, attrs)

  def change_action_item(action_item \\ %ActionItem{}, attrs \\ %{}), do: ActionItem.changeset(action_item, attrs)

  def publish_postmortem(attrs, %User{} = user), do: persist_new_postmortem(attrs, user)
  def publish_postmortem(_attrs, _user), do: {:error, :unauthorized}

  defp persist_new_postmortem(attrs, user) do
    Repo.transaction(fn ->
      with {:ok, postmortem} <-
             %Postmortem{}
             |> Postmortem.changeset(attrs)
             |> Ecto.Changeset.put_change(:created_by_user_id, user.id)
             |> Repo.insert(),
           {:ok, postmortem} <- put_domains(postmortem, attrs),
           :ok <- schedule_indexing(postmortem) do
        postmortem
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> finish_postmortem_transaction("postmortem.published", user)
  end

  def update_postmortem(%Postmortem{} = postmortem, attrs, %User{} = user) do
    if can_edit?(postmortem, user) do
      persist_updated_postmortem(postmortem, attrs, user)
    else
      {:error, :unauthorized}
    end
  end

  def update_postmortem(_postmortem, _attrs, _user), do: {:error, :unauthorized}

  def delete_postmortem(%Postmortem{} = postmortem, %User{} = user) do
    if can_delete?(postmortem, user) do
      postmortem
      |> Repo.delete()
      |> tap_result(fn deleted_postmortem ->
        record_postmortem_event("postmortem.deleted", deleted_postmortem, user)
      end)
    else
      {:error, :unauthorized}
    end
  end

  def delete_postmortem(_postmortem, _user), do: {:error, :unauthorized}

  defp persist_updated_postmortem(postmortem, attrs, user) do
    Repo.transaction(fn ->
      with {:ok, updated_postmortem} <-
             Repo.update(Postmortem.changeset(postmortem, attrs)),
           {:ok, updated_postmortem} <- put_domains(updated_postmortem, attrs),
           :ok <- schedule_indexing(updated_postmortem) do
        updated_postmortem
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> finish_postmortem_transaction("postmortem.updated", user)
  end

  defp finish_postmortem_transaction({:ok, postmortem}, action, user) do
    record_postmortem_event(action, postmortem, user)
    {:ok, postmortem}
  end

  defp finish_postmortem_transaction({:error, reason}, _action, _user), do: {:error, reason}

  def create_action_item(%Postmortem{} = postmortem, attrs, %User{} = user) do
    if can_edit?(postmortem, user) do
      %ActionItem{postmortem_id: postmortem.id}
      |> ActionItem.changeset(attrs)
      |> Repo.insert()
      |> tap_result(fn action_item ->
        record_action_item_event("postmortem.action_item_created", postmortem, action_item, user)
      end)
    else
      {:error, :unauthorized}
    end
  end

  def update_action_item(%Postmortem{} = postmortem, %ActionItem{} = action_item, attrs, %User{} = user) do
    if action_item.postmortem_id == postmortem.id and can_edit?(postmortem, user) do
      action_item
      |> ActionItem.changeset(attrs)
      |> Repo.update()
      |> tap_result(fn updated_action_item ->
        record_action_item_event(
          "postmortem.action_item_updated",
          postmortem,
          updated_action_item,
          user
        )
      end)
    else
      {:error, :unauthorized}
    end
  end

  def delete_action_item(%Postmortem{} = postmortem, %ActionItem{} = action_item, %User{} = user) do
    if action_item.postmortem_id == postmortem.id and can_edit?(postmortem, user) do
      action_item
      |> Repo.delete()
      |> tap_result(fn deleted_action_item ->
        record_action_item_event(
          "postmortem.action_item_deleted",
          postmortem,
          deleted_action_item,
          user
        )
      end)
    else
      {:error, :unauthorized}
    end
  end

  def toggle_action_item(%Postmortem{} = postmortem, %ActionItem{} = action_item, %User{} = user) do
    set_action_item_completed(postmortem, action_item, is_nil(action_item.completed_at), user)
  end

  def set_action_item_completed(%Postmortem{} = postmortem, %ActionItem{} = action_item, completed, %User{} = user)
      when is_boolean(completed) do
    cond do
      action_item.postmortem_id != postmortem.id or not can_edit?(postmortem, user) ->
        {:error, :unauthorized}

      completed == not is_nil(action_item.completed_at) ->
        {:ok, action_item}

      true ->
        persist_action_item_completion(postmortem, action_item, completed, user)
    end
  end

  def set_action_item_completed(_postmortem, _action_item, _completed, _user), do: {:error, :unauthorized}

  defp persist_action_item_completion(postmortem, action_item, completed, user) do
    completed_at = if completed, do: DateTime.utc_now() |> DateTime.truncate(:second)

    action =
      if completed,
        do: "postmortem.action_item_completed",
        else: "postmortem.action_item_reopened"

    action_item
    |> Changeset.change(completed_at: completed_at)
    |> Repo.update()
    |> tap_result(fn updated_action_item ->
      record_action_item_event(action, postmortem, updated_action_item, user)
    end)
  end

  def index_postmortem(postmortem_id, content_hash, opts \\ []) do
    embed = Keyword.get(opts, :embed, &embed/1)

    case Repo.get(Postmortem, postmortem_id) do
      nil ->
        {:error, :not_found}

      postmortem ->
        index_current_postmortem(postmortem, content_hash, embed)
    end
  end

  defp index_current_postmortem(postmortem, content_hash, embed) do
    if content_hash == content_hash(postmortem.body),
      do: index_embedding(postmortem, content_hash, embed),
      else: {:ok, :stale}
  end

  defp index_embedding(postmortem, content_hash, embed) do
    case Repo.get_by(Embedding, postmortem_id: postmortem.id) do
      %Embedding{status: :indexed, content_hash: ^content_hash} = embedding ->
        {:ok, embedding}

      _embedding ->
        generate_embedding(postmortem, content_hash, embed)
    end
  end

  defp generate_embedding(postmortem, content_hash, embed) do
    case embed.(embedding_input(postmortem.body)) do
      {:ok, vector} -> save_embedding(postmortem.id, content_hash, vector)
      {:error, reason} -> {:error, reason}
    end
  end

  def mark_embedding_failed(postmortem_id, content_hash, reason) do
    case Repo.get_by(Embedding, postmortem_id: postmortem_id, content_hash: content_hash) do
      nil ->
        :ok

      embedding ->
        embedding
        |> Embedding.changeset(%{status: :failed, failure_reason: to_string(reason)})
        |> Repo.update()

        :ok
    end
  end

  def semantic_search(query, opts \\ []) when is_binary(query) do
    embed = Keyword.get(opts, :embed, &embed/1)
    limit = Keyword.get(opts, :limit, 10)

    with {:ok, query_embedding} <- embed.(query) do
      results =
        Embedding
        |> where([embedding], embedding.status == :indexed)
        |> join(:inner, [embedding], postmortem in assoc(embedding, :postmortem), as: :postmortem)
        |> preload([postmortem: postmortem], postmortem: postmortem)
        |> Repo.all()
        |> Enum.map(fn embedding ->
          %{
            postmortem: embedding.postmortem,
            score: cosine_similarity(query_embedding, embedding.embedding)
          }
        end)
        |> Enum.sort_by(& &1.score, :desc)
        |> Enum.take(limit)

      {:ok, results}
    end
  end

  def title(%Postmortem{body: body}), do: title(body)

  def title(body) when is_binary(body) do
    body
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case Regex.run(~r/^\s*#\s+(.+)\s*$/, line) do
        [_, title] -> Markdown.preview(title, 100)
        _no_heading -> nil
      end
    end)
    |> case do
      "" -> "Postmortem"
      nil -> "Postmortem"
      title -> title
    end
  end

  defp maybe_search(query, value) when is_binary(value) and value != "" do
    where(query, [postmortem], ilike(postmortem.body, ^"%#{value}%"))
  end

  defp maybe_search(query, _value), do: query

  defp maybe_filter_published(query, :last_30_days) do
    where(
      query,
      [postmortem],
      postmortem.inserted_at >= ^DateTime.add(DateTime.utc_now(), -30, :day)
    )
  end

  defp maybe_filter_published(query, _value), do: query

  defp action_items_query do
    from action_item in ActionItem,
      order_by: [
        asc_nulls_first: action_item.completed_at,
        asc:
          fragment(
            "CASE ? WHEN 'immediate' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 WHEN 'low' THEN 3 END",
            action_item.priority
          ),
        asc: action_item.inserted_at
      ]
  end

  defp preload_postmortem(query) do
    preload(query, [:created_by_user, :domains, action_items: ^action_items_query()])
  end

  defp reference_identifier(reference) do
    reference = String.trim(reference)

    case URI.parse(reference) do
      %URI{path: path} when is_binary(path) and path != "" ->
        path
        |> String.split("/", trim: true)
        |> postmortem_path_number()
        |> Kernel.||(reference)

      _uri ->
        reference
    end
  end

  defp postmortem_path_number(["postmortems", number | _rest]), do: number
  defp postmortem_path_number([_segment | rest]), do: postmortem_path_number(rest)
  defp postmortem_path_number([]), do: nil

  defp public_number?(identifier), do: match?({_number, ""}, Integer.parse(identifier))

  defp schedule_indexing(postmortem) do
    content_hash = content_hash(postmortem.body)

    case Repo.get_by(Embedding, postmortem_id: postmortem.id) do
      %Embedding{content_hash: ^content_hash} ->
        :ok

      _embedding ->
        with {:ok, _embedding} <- put_pending_embedding(postmortem.id, content_hash),
             {:ok, _job} <- EmbeddingWorker.enqueue(postmortem.id, content_hash) do
          :ok
        end
    end
  end

  defp put_pending_embedding(postmortem_id, content_hash) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Embedding{}
    |> Embedding.changeset(%{
      postmortem_id: postmortem_id,
      content_hash: content_hash,
      status: :pending,
      embedding: nil,
      failure_reason: nil,
      indexed_at: nil
    })
    |> Repo.insert(
      on_conflict: [
        set: [
          content_hash: content_hash,
          status: :pending,
          embedding: nil,
          failure_reason: nil,
          indexed_at: nil,
          updated_at: now
        ]
      ],
      conflict_target: :postmortem_id,
      returning: true
    )
  end

  defp save_embedding(postmortem_id, content_hash, vector) when is_list(vector) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Embedding
    |> where(
      [embedding],
      embedding.postmortem_id == ^postmortem_id and embedding.content_hash == ^content_hash
    )
    |> select([embedding], embedding)
    |> Repo.update_all(
      set: [
        status: :indexed,
        embedding: vector,
        failure_reason: nil,
        indexed_at: now,
        updated_at: now
      ]
    )
    |> case do
      {1, [embedding]} -> {:ok, embedding}
      {0, []} -> {:ok, :stale}
    end
  end

  # Atlas has no ReqLLM. Reuse the OpenAI-compatible embedding client that
  # Atlas.Documents.Embedding already talks to.
  defp embed(body) do
    case Atlas.Documents.Embedding.embed(body) do
      {:ok, %{embedding: vector}} when is_list(vector) -> {:ok, vector}
      {:error, :missing_configuration} -> {:error, :embedding_not_configured}
      {:error, reason} -> {:error, reason}
    end
  end

  # Postmortem bodies are unbounded prose while embedding models cap their
  # input, so long incidents are indexed on their opening sections instead of
  # being rejected by the provider.
  defp embedding_input(body), do: String.slice(body, 0, @embedding_input_limit)

  defp content_hash(body), do: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

  # Local replacement for ReqLLM.cosine_similarity, kept identical in intent.
  defp cosine_similarity(a, b) when is_list(a) and is_list(b) do
    {dot, mag_a, mag_b} =
      Enum.zip(a, b)
      |> Enum.reduce({0.0, 0.0, 0.0}, fn {x, y}, {dot, mag_a, mag_b} ->
        {dot + x * y, mag_a + x * x, mag_b + y * y}
      end)

    denom = :math.sqrt(mag_a) * :math.sqrt(mag_b)
    if denom == 0.0, do: 0.0, else: dot / denom
  end

  defp put_domains(postmortem, attrs) do
    case fetch_domain_ids(attrs) do
      :error ->
        {:ok, Repo.preload(postmortem, :domains)}

      {:ok, values} ->
        domain_ids = values |> List.wrap() |> Enum.reject(&(&1 in [nil, ""]))
        domains = Repo.all(from domain in Domain, where: domain.id in ^domain_ids)

        if length(domains) == length(Enum.uniq(domain_ids)) do
          postmortem
          |> Repo.preload(:domains)
          |> Changeset.change()
          |> Changeset.put_assoc(:domains, domains)
          |> Repo.update()
        else
          {:error,
           Changeset.add_error(
             Changeset.change(postmortem),
             :domain_ids,
             "contains unknown domains"
           )}
        end
    end
  end

  defp fetch_domain_ids(attrs) do
    case Map.fetch(attrs, "domain_ids") do
      :error -> Map.fetch(attrs, :domain_ids)
      result -> result
    end
  end

  defp tap_result({:ok, value} = result, fun) do
    fun.(value)
    result
  end

  defp tap_result(result, _fun), do: result

  defp record_postmortem_event(action, postmortem, user) do
    Audit.record(action, %{
      actor: user,
      target_type: "postmortem",
      target_id: postmortem.id,
      target_label: title(postmortem),
      metadata: %{
        "number" => to_string(postmortem.number),
        "path" => "/engineering/postmortems/#{postmortem.number}"
      }
    })
  end

  defp record_action_item_event(action, postmortem, action_item, user) do
    Audit.record(action, %{
      actor: user,
      target_type: "postmortem",
      target_id: postmortem.id,
      target_label: title(postmortem),
      metadata: %{
        "action_item_id" => action_item.id,
        "action_item_priority" => Atom.to_string(action_item.priority),
        "action_item_title" => action_item.title,
        "number" => to_string(postmortem.number),
        "path" => "/engineering/postmortems/#{postmortem.number}"
      }
    })
  end
end
