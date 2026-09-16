defmodule Atlas.Memory do
  @moduledoc """
  Atlas's memory subsystem, inspired by spacebot.sh.

  The Slack agent curates memory by calling `memory_save` and reads it back
  via `memory_recall`. A debounced background job synthesizes a bulletin that
  is prepended to the agent's system prompt on every thread.

  Memory can be scoped to the company workspace globally or to the Slack
  channel where it was captured.

  Embeddings live in the in-cluster OpenData Vector service, keyed by
  `"memory_node:<id>"`, following the same pattern as `Atlas.Documents`.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Documents.Embedding
  alias Atlas.Memory.Bulletin
  alias Atlas.Memory.Edge
  alias Atlas.Memory.Node
  alias Atlas.Memory.Workers.LinkNode
  alias Atlas.Memory.Workers.RefreshBulletin
  alias Atlas.Repo
  alias Atlas.Vector

  require Logger

  @vector_source_type "memory_node"

  @rrf_k 60
  @default_search_limit 10
  @search_vector_timeout 1_000
  @search_embedding_receive_timeout 1_000
  @search_vector_receive_timeout 1_000

  @doc """
  Creates a memory node and indexes its body in the vector service.

  Vector indexing is best-effort: when the embedding service is not configured
  or fails, the node is persisted without an embedding and lexical search
  still finds it.
  """
  def create_node(attrs) when is_map(attrs) do
    {workflow_attrs, public_attrs} = split_workflow_attrs(attrs)

    %Node{}
    |> Node.changeset(public_attrs)
    |> Node.workflow_changeset(workflow_attrs)
    |> stamp_associations(attrs)
    |> Repo.insert()
    |> case do
      {:ok, %Node{confirmation: :pending} = node} ->
        audit_node("memory_node.created", node, %{})
        {:ok, node}

      {:ok, node} ->
        node = index_node_vector(node)
        audit_node("memory_node.created", node, %{})
        {:ok, node}

      {:error, _changeset} = error ->
        error
    end
  end

  defp split_workflow_attrs(attrs) do
    workflow_keys =
      Node.workflow_fields() ++ Enum.map(Node.workflow_fields(), &Atom.to_string/1)

    {Map.take(attrs, workflow_keys), Map.drop(attrs, workflow_keys)}
  end

  defp stamp_associations(changeset, attrs) do
    changeset
    |> stamp_assoc(:slack_channel_id, attrs)
    |> stamp_assoc(:slack_user_id, attrs)
    |> stamp_assoc(:source_slack_message_id, attrs)
  end

  defp stamp_assoc(changeset, key, attrs) do
    string_key = Atom.to_string(key)

    case Map.get(attrs, key) || Map.get(attrs, string_key) do
      nil -> changeset
      value -> Ecto.Changeset.put_change(changeset, key, value)
    end
  end

  def get_node(id) when is_binary(id), do: Repo.get(Node, id)

  def change_node(%Node{} = node, attrs \\ %{}) do
    Node.changeset(node, attrs)
  end

  @doc """
  Updates an existing memory node.

  Body edits are reindexed in the vector store. Forgetting removes the vector
  entry, and restoring a forgotten node recreates it on a best-effort basis.
  """
  def update_node(%Node{} = node, attrs) when is_map(attrs) do
    changeset = Node.changeset(node, attrs)
    body_changed? = Map.has_key?(changeset.changes, :body)
    forgotten_changed? = Map.has_key?(changeset.changes, :forgotten)

    case Repo.update(changeset) do
      {:ok, node} ->
        node = sync_node_vector_after_update(node, body_changed?, forgotten_changed?)
        audit_node(node_update_action(changeset), node, %{changed_fields: changed_fields(changeset)})
        {:ok, node}

      {:error, _changeset} = error ->
        error
    end
  end

  @doc """
  Creates an edge between two memory nodes. Returns
  `{:ok, edge}` on insert, `{:ok, existing}` on conflict (idempotent on
  `(src_id, dst_id, kind)`), or `{:error, changeset}` for validation errors.
  """
  def create_edge(attrs) when is_map(attrs) do
    %Edge{}
    |> Edge.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, edge} ->
        audit_edge(edge)
        {:ok, edge}

      {:error, changeset} ->
        fallback_existing_edge(changeset)
    end
  end

  defp fallback_existing_edge(%Ecto.Changeset{} = changeset) do
    src_id = Ecto.Changeset.get_field(changeset, :src_id)
    dst_id = Ecto.Changeset.get_field(changeset, :dst_id)
    kind = Ecto.Changeset.get_field(changeset, :kind)

    if src_id && dst_id && kind do
      case Repo.get_by(Edge, src_id: src_id, dst_id: dst_id, kind: kind) do
        %Edge{} = existing -> {:ok, existing}
        nil -> {:error, changeset}
      end
    else
      {:error, changeset}
    end
  end

  @doc "Lists edges where the given node is the source, optionally filtered by kind."
  def list_edges_by_src(node_or_id, kind \\ nil)
  def list_edges_by_src(%Node{id: id}, kind), do: list_edges_by_src(id, kind)

  def list_edges_by_src(id, kind) when is_binary(id) do
    Edge
    |> where([e], e.src_id == ^id)
    |> maybe_filter_edge_kind(kind)
    |> Repo.all()
  end

  @doc "Lists incoming and outgoing edges for a memory node with adjacent nodes preloaded."
  def list_node_edges(%Node{id: id}) do
    outgoing =
      Edge
      |> where([e], e.src_id == ^id)
      |> preload(:dst)
      |> order_by([e], asc: e.kind, desc: e.weight, desc: e.inserted_at)
      |> Repo.all()

    incoming =
      Edge
      |> where([e], e.dst_id == ^id)
      |> preload(:src)
      |> order_by([e], asc: e.kind, desc: e.weight, desc: e.inserted_at)
      |> Repo.all()

    %{outgoing: outgoing, incoming: incoming}
  end

  @doc "Lists edges where the given node is the destination, optionally filtered by kind."
  def list_edges_by_dst(node_or_id, kind \\ nil)
  def list_edges_by_dst(%Node{id: id}, kind), do: list_edges_by_dst(id, kind)

  def list_edges_by_dst(id, kind) when is_binary(id) do
    Edge
    |> where([e], e.dst_id == ^id)
    |> maybe_filter_edge_kind(kind)
    |> Repo.all()
  end

  defp maybe_filter_edge_kind(query, nil), do: query

  defp maybe_filter_edge_kind(query, kind) when is_atom(kind), do: where(query, [e], e.kind == ^kind)

  @doc """
  Marks a memory node as forgotten and removes its vector entry. Forgotten
  nodes are excluded from search results.
  """
  def forget_node(%Node{} = node) do
    update_node(node, %{forgotten: true})
  end

  @doc """
  Restores a forgotten memory node and reindexes it for recall.
  """
  def restore_node(%Node{} = node) do
    update_node(node, %{forgotten: false})
  end

  @doc """
  Promotes a pending memory node to confirmed, making it available to recall
  and the bulletin. Triggers a debounced bulletin refresh.
  """
  def confirm_node(%Node{confirmation: :confirmed} = node), do: {:ok, node}

  def confirm_node(%Node{} = node) do
    node
    |> Node.workflow_changeset(%{confirmation: :confirmed})
    |> Repo.update()
    |> case do
      {:ok, confirmed} ->
        confirmed = index_node_vector(confirmed)
        RefreshBulletin.schedule_debounced(confirmed.scope)
        audit_node("memory_node.confirmed", confirmed, %{})
        {:ok, confirmed}

      error ->
        error
    end
  end

  @doc """
  Discards a pending memory node by marking it forgotten. Mirrors how forget
  cleans up the vector index, so the proposal disappears from every search
  path without leaving a confirmation gap.
  """
  def discard_node(%Node{} = node) do
    forget_node(node)
  end

  @doc """
  Looks up the pending memory node anchored to a Slack proposal message
  identified by `(slack_channel_id, proposal_slack_ts)`. Returns nil when no
  matching pending node exists.
  """
  def get_pending_node_by_proposal(slack_channel_id, proposal_slack_ts)
      when is_binary(slack_channel_id) and is_binary(proposal_slack_ts) do
    Node
    |> where([n], n.slack_channel_id == ^slack_channel_id)
    |> where([n], n.proposal_slack_ts == ^proposal_slack_ts)
    |> where([n], n.confirmation == :pending)
    |> where([n], n.forgotten == false)
    |> Repo.one()
  end

  def get_pending_node_by_proposal(_channel_id, _ts), do: nil

  @doc """
  Lists memory nodes for a scope, newest first. Excludes forgotten nodes
  unless `include_forgotten: true` is passed or `status: :forgotten`
  explicitly requests them. Excludes pending (unconfirmed) nodes unless
  `include_pending: true` is passed or `confirmation: :pending` explicitly
  requests them.
  """
  def list_nodes(opts \\ []) do
    scope = Keyword.get(opts, :scope, :global)
    limit = Keyword.get(opts, :limit, 50)
    kind = Keyword.get(opts, :kind)
    query = Keyword.get(opts, :query)
    status = Keyword.get(opts, :status)
    confirmation = Keyword.get(opts, :confirmation)
    slack_channel_id = Keyword.get(opts, :slack_channel_id)
    include_forgotten? = Keyword.get(opts, :include_forgotten, false)
    include_pending? = Keyword.get(opts, :include_pending, false)

    Node
    |> where([n], n.scope == ^scope)
    |> maybe_filter_slack_channel(slack_channel_id)
    |> maybe_filter_kind(kind)
    |> maybe_filter_node_query(query)
    |> maybe_filter_status(status, include_forgotten?)
    |> maybe_filter_confirmation(confirmation, include_pending?)
    |> order_by([n], desc: n.inserted_at, desc: n.id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_filter_kind(query, nil), do: query
  defp maybe_filter_kind(query, kind) when is_atom(kind), do: where(query, [n], n.kind == ^kind)

  defp maybe_filter_slack_channel(query, nil), do: query

  defp maybe_filter_slack_channel(query, channel_id) when is_binary(channel_id) do
    where(query, [n], n.slack_channel_id == ^channel_id)
  end

  defp maybe_filter_node_query(query, nil), do: query

  defp maybe_filter_node_query(query, value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        query

      trimmed ->
        pattern = "%#{escaped_like(trimmed)}%"

        where(
          query,
          [n],
          fragment("to_tsvector('english', ?) @@ websearch_to_tsquery('english', ?)", n.body, ^trimmed) or
            ilike(n.body, ^pattern)
        )
    end
  end

  defp escaped_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp maybe_filter_status(query, :active, _include_forgotten?), do: where(query, [n], n.forgotten == false)
  defp maybe_filter_status(query, :forgotten, _include_forgotten?), do: where(query, [n], n.forgotten == true)
  defp maybe_filter_status(query, _status, true), do: query
  defp maybe_filter_status(query, _status, _include_forgotten?), do: where(query, [n], n.forgotten == false)

  defp maybe_filter_confirmation(query, :pending, _include_pending?), do: where(query, [n], n.confirmation == :pending)

  defp maybe_filter_confirmation(query, :confirmed, _include_pending?),
    do: where(query, [n], n.confirmation == :confirmed)

  defp maybe_filter_confirmation(query, _confirmation, true), do: query

  defp maybe_filter_confirmation(query, _confirmation, _include_pending?),
    do: where(query, [n], n.confirmation == :confirmed)

  @doc """
  Searches memory using a hybrid of vector similarity and Postgres full-text
  search. Returns `Atlas.Memory.Node` structs ordered by combined score, with
  `access_count` and `last_accessed_at` bumped for each hit.
  """
  def search_nodes(query, opts \\ []) when is_binary(query) do
    scope = Keyword.get(opts, :scope, :global)
    kind = Keyword.get(opts, :kind)
    slack_channel_id = Keyword.get(opts, :slack_channel_id)
    limit = Keyword.get(opts, :limit, @default_search_limit)

    case String.trim(query) do
      "" ->
        []

      trimmed ->
        trimmed
        |> hybrid_search(opts, limit * 3)
        |> hydrate_hits(scope, kind, slack_channel_id, limit)
        |> bump_recall_counters()
    end
  end

  defp hybrid_search(query, opts, candidate_pool) do
    vector_task = Task.async(fn -> vector_candidates(query, opts, candidate_pool) end)
    fulltext_results = fulltext_candidates(query, opts, candidate_pool)

    [
      await_vector_candidates(vector_task, Keyword.get(opts, :vector_timeout, @search_vector_timeout)),
      fulltext_results
    ]
    |> reciprocal_rank_fusion(candidate_pool)
  end

  defp vector_candidates(query, opts, limit) do
    if Vector.configured?() do
      with {:ok, %{embedding: embedding}} <-
             Embedding.embed(query, search_embedding_opts(opts)),
           {:ok, body} <-
             Vector.search(embedding,
               k: limit,
               receive_timeout: Keyword.get(opts, :vector_receive_timeout, @search_vector_receive_timeout),
               filter: %{"eq" => %{"field" => "source_type", "value" => @vector_source_type}}
             ) do
        body |> extract_hits() |> Enum.map(&{&1.node_id, &1.score})
      else
        _ -> []
      end
    else
      []
    end
  end

  defp await_vector_candidates(task, timeout) do
    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, results} when is_list(results) -> results
      _ -> []
    end
  end

  defp search_embedding_opts(opts) do
    Keyword.put_new(opts, :receive_timeout, @search_embedding_receive_timeout)
  end

  defp fulltext_candidates(query, opts, limit) do
    scope = Keyword.get(opts, :scope, :global)
    slack_channel_id = Keyword.get(opts, :slack_channel_id)

    Node
    |> where([node], fragment("to_tsvector('english', ?) @@ websearch_to_tsquery('english', ?)", node.body, ^query))
    |> where([node], node.scope == ^scope)
    |> maybe_filter_slack_channel(slack_channel_id)
    |> where([node], node.forgotten == false)
    |> where([node], node.confirmation == :confirmed)
    |> order_by(
      [node],
      desc:
        fragment(
          "ts_rank(to_tsvector('english', ?), websearch_to_tsquery('english', ?))",
          node.body,
          ^query
        )
    )
    |> limit(^limit)
    |> select(
      [node],
      {node.id,
       fragment(
         "ts_rank(to_tsvector('english', ?), websearch_to_tsquery('english', ?))",
         node.body,
         ^query
       )}
    )
    |> Repo.all()
  end

  defp reciprocal_rank_fusion(ranked_lists, limit) do
    ranked_lists
    |> Enum.flat_map(fn list ->
      list
      |> Enum.with_index(1)
      |> Enum.map(fn {{id, _score}, rank} -> {id, 1.0 / (@rrf_k + rank)} end)
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {id, contributions} -> {id, Enum.sum(contributions)} end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.take(limit)
  end

  defp extract_hits(%{"results" => results}) when is_list(results) do
    results
    |> Enum.map(&parse_hit/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_hits(_), do: []

  defp parse_hit(%{"id" => @vector_source_type <> ":" <> node_id} = result) do
    %{node_id: node_id, score: result["score"] || result["distance"]}
  end

  defp parse_hit(_), do: nil

  defp hydrate_hits([], _scope, _kind, _slack_channel_id, _limit), do: []

  defp hydrate_hits(hits, scope, kind, slack_channel_id, limit) do
    ranking = Map.new(hits, fn {id, score} -> {id, score} end)
    ids = Map.keys(ranking)

    nodes =
      Node
      |> where([n], n.id in ^ids)
      |> where([n], n.scope == ^scope)
      |> where([n], n.forgotten == false)
      |> where([n], n.confirmation == :confirmed)
      |> maybe_filter_slack_channel(slack_channel_id)
      |> maybe_filter_kind(kind)
      |> Repo.all()

    nodes
    |> apply_supersession()
    |> apply_contradiction()
    |> Enum.sort_by(fn node -> -Map.get(ranking, node.id, 0.0) * node.importance end)
    |> Enum.take(limit)
  end

  # Drop nodes that are the dst of an :updates edge whose src is also in the
  # result set. When both the updater and the superseded target are returned by
  # search, only the updater should reach the caller.
  defp apply_supersession(nodes) do
    ids = Enum.map(nodes, & &1.id)
    superseded = superseded_dst_ids(ids)
    Enum.reject(nodes, &(&1.id in superseded))
  end

  # Drop the older of any two nodes connected by a :contradicts edge when both
  # are in the result set. Newer wins.
  defp apply_contradiction(nodes) do
    by_id = Map.new(nodes, &{&1.id, &1})
    ids = Map.keys(by_id)
    pairs = contradiction_pairs(ids)

    losers =
      Enum.reduce(pairs, MapSet.new(), fn {a_id, b_id}, acc ->
        case {Map.get(by_id, a_id), Map.get(by_id, b_id)} do
          {nil, _} -> acc
          {_, nil} -> acc
          {a, b} -> MapSet.put(acc, older_id(a, b))
        end
      end)

    Enum.reject(nodes, &MapSet.member?(losers, &1.id))
  end

  defp older_id(a, b) do
    case DateTime.compare(naive_to_dt(a.inserted_at), naive_to_dt(b.inserted_at)) do
      :lt -> a.id
      _ -> b.id
    end
  end

  defp naive_to_dt(%NaiveDateTime{} = dt), do: DateTime.from_naive!(dt, "Etc/UTC")
  defp naive_to_dt(%DateTime{} = dt), do: dt

  defp superseded_dst_ids([]), do: []

  defp superseded_dst_ids(ids) do
    Edge
    |> where([e], e.kind == :updates)
    |> where([e], e.src_id in ^ids and e.dst_id in ^ids)
    |> select([e], e.dst_id)
    |> Repo.all()
  end

  defp contradiction_pairs([]), do: []

  defp contradiction_pairs(ids) do
    Edge
    |> where([e], e.kind == :contradicts)
    |> where([e], e.src_id in ^ids and e.dst_id in ^ids)
    |> select([e], {e.src_id, e.dst_id})
    |> Repo.all()
  end

  defp bump_recall_counters([]), do: []

  defp bump_recall_counters(nodes) do
    ids = Enum.map(nodes, & &1.id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {_count, _} =
      Node
      |> where([n], n.id in ^ids)
      |> Repo.update_all(
        inc: [access_count: 1],
        set: [last_accessed_at: now, updated_at: now]
      )

    nodes
  end

  defp index_node_vector(%Node{} = node) do
    case Embedding.embed(node.body) do
      {:ok, %{embedding: embedding, model: model}} ->
        upsert_node_vector(node, embedding)

        node =
          node
          |> Node.embedding_changeset(model, DateTime.utc_now())
          |> Repo.update!()

        _ = LinkNode.enqueue(node)
        node

      {:error, reason} ->
        Logger.warning("Memory embedding skipped: #{inspect(reason)}")
        node
    end
  end

  defp upsert_node_vector(%Node{} = node, embedding) do
    Vector.upsert_vectors([
      %{
        id: vector_id(node),
        vector: embedding,
        attributes: %{
          "source_type" => @vector_source_type,
          "scope" => Atom.to_string(node.scope),
          "slack_channel_id" => node.slack_channel_id
        }
      }
    ])
  end

  defp delete_node_vector(%Node{} = node) do
    Vector.delete_vectors([vector_id(node)])
  end

  defp sync_node_vector_after_update(%Node{forgotten: true} = node, _body_changed?, _forgotten_changed?) do
    delete_node_vector(node)
    node
  end

  defp sync_node_vector_after_update(%Node{} = node, body_changed?, forgotten_changed?)
       when body_changed? or forgotten_changed? do
    index_node_vector(node)
  end

  defp sync_node_vector_after_update(%Node{} = node, _body_changed?, _forgotten_changed?), do: node

  defp vector_id(%Node{id: id}), do: "#{@vector_source_type}:#{id}"

  @doc "Returns the bulletin for a scope, or nil when none has been generated."
  def get_bulletin(scope) when scope in [:global, :channel] do
    Bulletin
    |> where([b], b.scope == ^scope and is_nil(b.slack_channel_id))
    |> Repo.one()
  end

  def get_bulletin(scope, channel_id) when scope == :channel and is_binary(channel_id) do
    Bulletin
    |> where([b], b.scope == ^scope and b.slack_channel_id == ^channel_id)
    |> Repo.one()
  end

  @doc """
  Replaces the bulletin body for a scope in a single atomic upsert. The
  previous body is overwritten only on success; a failed synthesis leaves
  the stale bulletin in place by virtue of not calling this function.
  """
  def upsert_bulletin(scope, body, opts \\ []) when scope in [:global, :channel] and is_binary(body) do
    channel_id = Keyword.get(opts, :slack_channel_id)

    base =
      case get_bulletin_for(scope, channel_id) do
        nil -> %Bulletin{}
        bulletin -> bulletin
      end

    result =
      base
      |> Bulletin.changeset(%{scope: scope, body: body})
      |> Ecto.Changeset.put_change(:slack_channel_id, channel_id)
      |> Repo.insert_or_update()

    case result do
      {:ok, bulletin} ->
        Audit.record("memory_bulletin.refreshed", %{
          target_type: "memory_bulletin",
          target_id: bulletin.id,
          target_label: Atom.to_string(bulletin.scope),
          metadata: %{
            "path" => "/memory",
            "scope" => Atom.to_string(bulletin.scope),
            "slack_channel_id" => bulletin.slack_channel_id,
            "body_length" => String.length(bulletin.body)
          }
        })

        {:ok, bulletin}

      {:error, _changeset} = error ->
        error
    end
  end

  defp get_bulletin_for(:global, _), do: get_bulletin(:global)

  defp get_bulletin_for(:channel, channel_id) when is_binary(channel_id), do: get_bulletin(:channel, channel_id)

  defp get_bulletin_for(_, _), do: nil

  defp node_update_action(changeset) do
    case Ecto.Changeset.get_change(changeset, :forgotten) do
      true -> "memory_node.forgotten"
      false -> "memory_node.restored"
      nil -> "memory_node.updated"
    end
  end

  defp changed_fields(changeset) do
    changeset.changes
    |> Map.keys()
    |> Enum.map(&Atom.to_string/1)
    |> Enum.sort()
  end

  defp audit_node(action, %Node{} = node, metadata) do
    Audit.record(action, %{
      target_type: "memory_node",
      target_id: node.id,
      target_label: Atom.to_string(node.kind),
      metadata:
        Map.merge(
          %{
            "path" => "/memory/#{node.id}",
            "scope" => Atom.to_string(node.scope),
            "kind" => Atom.to_string(node.kind),
            "confirmation" => Atom.to_string(node.confirmation),
            "forgotten" => node.forgotten,
            "slack_channel_id" => node.slack_channel_id,
            "source_slack_message_id" => node.source_slack_message_id
          },
          metadata
        )
    })
  end

  defp audit_edge(%Edge{} = edge) do
    Audit.record("memory_edge.created", %{
      target_type: "memory_edge",
      target_id: edge.id,
      target_label: Atom.to_string(edge.kind),
      metadata: %{
        "source_node_id" => edge.src_id,
        "destination_node_id" => edge.dst_id,
        "kind" => Atom.to_string(edge.kind),
        "weight" => edge.weight
      }
    })
  end
end
