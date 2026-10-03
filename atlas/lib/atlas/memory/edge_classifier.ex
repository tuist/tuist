defmodule Atlas.Memory.EdgeClassifier do
  @moduledoc """
  Single-turn Condukt agent that classifies the relationship between a newly
  saved memory node and each of its nearest neighbours.

  One LLM call per new node regardless of candidate count: all candidates are
  classified together via structured output. Possible relations:

    - `related_to`  — semantically connected, neither supersedes the other
    - `updates`     — the new node supersedes the existing one
    - `contradicts` — the new node conflicts with the existing one
    - `none`        — drop, not actually related

  Direction convention: `src` is the new node, `dst` is the existing candidate.
  """

  use Condukt

  alias Atlas.Agents.Sessions
  alias Atlas.Agents.StyleGuide
  alias Atlas.LLMs.Runner
  alias Atlas.Memory.Node

  @impl true
  def tools, do: []

  @impl true
  def system_prompt do
    """
    You classify the relationship between a newly saved memory item and each
    of its nearest existing neighbours.

    For each candidate, return exactly one of:

    - related_to: same topic, but the new item does not supersede or
      contradict the existing one.
    - updates: the new item supersedes or refines the existing one (a newer
      decision, a corrected fact, an updated identity claim). Use this only
      when the two items make claims about the same thing and the new claim
      replaces the older one.
    - contradicts: the new item and the existing item make incompatible
      claims about the same thing, with no clear supersession.
    - none: the candidate is not actually related. Use this to drop weak
      matches the vector search surfaced.

    Be conservative. Default to `related_to` for general topical overlap;
    reserve `updates` and `contradicts` for clear cases. Do not fabricate
    a relationship that the text does not justify.

    #{StyleGuide.prose_rules()}
    """
  end

  @doc """
  Classifies the new node against each candidate. Returns
  `{:ok, [%{candidate_id, relation}]}` where `relation` is one of
  `:related_to`, `:updates`, `:contradicts`, or `:none`. Empty candidates
  yield `{:ok, []}` without an LLM call.
  """
  def classify(%Node{} = _new_node, []), do: {:ok, []}

  def classify(%Node{} = new_node, candidates) when is_list(candidates) do
    case Runner.fetch_config() do
      {:ok, llm} ->
        Sessions.run(
          __MODULE__,
          prompt(new_node, candidates),
          Runner.client_opts(llm) ++
            [
              max_turns: 1,
              load_project_instructions: false,
              output: output_schema()
            ]
        )
        |> normalize(candidates)

      {:error, :llm_not_configured} = error ->
        error
    end
  end

  defp prompt(%Node{} = new_node, candidates) do
    candidate_lines =
      candidates
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {%Node{} = c, idx} ->
        "#{idx}. id=#{c.id} kind=#{c.kind} body=#{inspect(c.body)}"
      end)

    """
    Classify the relationship between this new memory item and each
    candidate.

    New item:
      kind=#{new_node.kind}
      body=#{inspect(new_node.body)}

    Candidates:
    #{candidate_lines}

    Return one entry per candidate using the exact id from the list.
    """
  end

  defp output_schema do
    %{
      type: "object",
      required: ["relations"],
      properties: %{
        relations: %{
          type: "array",
          items: %{
            type: "object",
            required: ["candidate_id", "relation"],
            properties: %{
              candidate_id: %{type: "string"},
              relation: %{
                type: "string",
                enum: ["related_to", "updates", "contradicts", "none"]
              }
            }
          }
        }
      }
    }
  end

  defp normalize({:ok, %{"relations" => relations}}, candidates) when is_list(relations) do
    candidate_ids = MapSet.new(candidates, & &1.id)

    parsed =
      relations
      |> Enum.map(&parse_relation/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(fn %{candidate_id: id} -> MapSet.member?(candidate_ids, id) end)

    {:ok, parsed}
  end

  defp normalize({:ok, _other}, _candidates), do: {:ok, []}
  defp normalize({:error, _reason} = error, _candidates), do: error

  defp parse_relation(%{"candidate_id" => id, "relation" => relation}) when is_binary(id) do
    case relation_atom(relation) do
      nil -> nil
      atom -> %{candidate_id: id, relation: atom}
    end
  end

  defp parse_relation(_), do: nil

  defp relation_atom("related_to"), do: :related_to
  defp relation_atom("updates"), do: :updates
  defp relation_atom("contradicts"), do: :contradicts
  defp relation_atom("none"), do: :none
  defp relation_atom(_), do: nil
end
