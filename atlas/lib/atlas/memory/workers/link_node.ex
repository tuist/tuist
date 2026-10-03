defmodule Atlas.Memory.Workers.LinkNode do
  @moduledoc """
  Background job that links a newly saved memory node to its nearest
  neighbours.

  Pipeline per job:

    1. Look up the node and embed its body.
    2. Query the OpenData Vector service for the top K neighbours of the
       same source type.
    3. Hydrate the candidates from Postgres, dropping self, forgotten,
       and out-of-scope rows.
    4. Hand the candidates to `Atlas.Memory.EdgeClassifier`, which makes a
       single structured-output LLM call and returns one relation per
       candidate.
    5. Insert edges for `:related_to`, `:updates`, and `:contradicts`
       relations (skip `:none`).

  Every external call is best-effort. A missing node, an unconfigured
  vector service, or an unconfigured LLM cancels the job without retrying.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  alias Atlas.Documents.Embedding
  alias Atlas.LLMs.Errors, as: LLMErrors
  alias Atlas.Memory
  alias Atlas.Memory.EdgeClassifier
  alias Atlas.Memory.Node
  alias Atlas.Repo
  alias Atlas.Vector

  require Logger

  @candidate_limit 5
  @min_similarity 0.55

  def enqueue(%Node{id: id, forgotten: false}), do: enqueue(id)
  def enqueue(%Node{}), do: :ok

  def enqueue(node_id) when is_binary(node_id) do
    %{"node_id" => node_id}
    |> new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def enqueue(_), do: :ok

  @impl true
  def perform(%Oban.Job{args: %{"node_id" => node_id}}) when is_binary(node_id) do
    with %Node{} = node <- Memory.get_node(node_id),
         false <- node.forgotten,
         true <- Vector.configured?() || {:cancel, :vector_not_configured},
         {:ok, %{embedding: embedding}} <- Embedding.embed(node.body),
         {:ok, candidates} <- nearest_candidates(node, embedding) do
      link_candidates(node, candidates)
    else
      nil ->
        {:cancel, :node_not_found}

      true ->
        {:cancel, :node_forgotten}

      {:cancel, _reason} = cancel ->
        cancel

      {:error, reason} ->
        Logger.warning("Memory linking failed for #{node_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def perform(%Oban.Job{}), do: {:cancel, :missing_node_id}

  defp nearest_candidates(%Node{} = node, embedding) do
    case Vector.search(embedding,
           k: @candidate_limit + 1,
           filter: %{"eq" => %{"field" => "source_type", "value" => "memory_node"}}
         ) do
      {:ok, body} ->
        candidates =
          body
          |> extract_hits()
          |> Enum.reject(&(&1.id == node.id))
          |> Enum.filter(&(similarity_score(&1) >= @min_similarity))
          |> Enum.take(@candidate_limit)
          |> hydrate(node)

        {:ok, candidates}

      {:error, _reason} = error ->
        error
    end
  end

  defp extract_hits(%{"results" => results}) when is_list(results) do
    results
    |> Enum.map(fn result ->
      case result do
        %{"id" => "memory_node:" <> id} ->
          %{id: id, score: result["score"], distance: result["distance"]}

        _other ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_hits(_), do: []

  defp similarity_score(%{score: score}) when is_number(score), do: score
  defp similarity_score(%{distance: distance}) when is_number(distance), do: 1.0 - distance
  defp similarity_score(_), do: 0.0

  defp hydrate([], _node), do: []

  defp hydrate(hits, %Node{scope: scope}) do
    ids = Enum.map(hits, & &1.id)

    Node
    |> where([n], n.id in ^ids)
    |> where([n], n.scope == ^scope)
    |> where([n], n.forgotten == false)
    |> Repo.all()
  end

  defp link_candidates(_node, []), do: :ok

  defp link_candidates(%Node{} = node, candidates) do
    case EdgeClassifier.classify(node, candidates) do
      {:ok, relations} ->
        Enum.each(relations, &maybe_create_edge(node, &1))
        :ok

      {:error, :llm_not_configured} ->
        {:cancel, :llm_not_configured}

      {:error, reason} ->
        Logger.warning("Memory edge classification failed for #{node.id}: #{inspect(reason)}")
        LLMErrors.oban_error(reason)
    end
  end

  defp maybe_create_edge(_node, %{relation: :none}), do: :ok

  defp maybe_create_edge(%Node{id: src_id}, %{candidate_id: dst_id, relation: relation}) do
    case Memory.create_edge(%{src_id: src_id, dst_id: dst_id, kind: relation, weight: 1.0}) do
      {:ok, _edge} ->
        :ok

      {:error, reason} ->
        Logger.warning("Could not create memory edge #{src_id}->#{dst_id} #{relation}: #{inspect(reason)}")
        :ok
    end
  end
end
