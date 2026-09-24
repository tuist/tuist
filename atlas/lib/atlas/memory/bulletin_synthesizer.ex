defmodule Atlas.Memory.BulletinSynthesizer do
  @moduledoc """
  Single-turn Condukt agent that synthesizes a memory bulletin from the
  durable identity, decision, and goal nodes the agent has confirmed so far.

  Output is plain text intended to be prepended to the Slack agent's system
  prompt on every internal company channel thread. Because the bulletin
  leaks into every unrelated conversation by design, we deliberately cap its
  inputs to the kinds least likely to be conversation-specific: ephemeral
  kinds (`:event`, `:fact`, `:observation`, `:preference`, `:todo`) are
  still saved and recallable via `memory_recall`, but they no longer
  fan out via the always-prepended bulletin.
  """

  use Condukt

  alias Atlas.Agents.Sessions
  alias Atlas.Agents.StyleGuide
  alias Atlas.LLMs.Runner
  alias Atlas.Memory.Node

  @recent_limit 12
  @bulletin_kinds [:identity, :decision, :goal]

  @doc "Kinds that feed the always-prepended bulletin. Other kinds are recall-only."
  def bulletin_kinds, do: @bulletin_kinds

  @impl true
  def tools, do: []

  @impl true
  def system_prompt do
    """
    You produce a concise memory bulletin for the Atlas Slack assistant.

    The bulletin is prepended to the assistant's system prompt on every
    thread, so it must read like ambient context, not a report:

    - One or two short paragraphs total, around 120 words combined.
    - Lead with durable identities, then decisions, then open goals.
    - Refer to people and accounts by name, not memory IDs.
    - Omit empty sections; do not announce gaps ("no recent decisions").
    - Do not invent facts. Use only what the input lists.
    - Plain prose, no markdown headers, no bullet lists.

    #{StyleGuide.prose_rules()}
    """
  end

  def synthesize_global do
    nodes = bulletin_input_nodes()

    if nodes == [] do
      {:ok, :empty}
    else
      case Runner.fetch_config() do
        {:ok, llm} ->
          Sessions.run(
            __MODULE__,
            prompt(nodes),
            Runner.client_opts(llm) ++ [max_turns: 1, load_project_instructions: false]
          )
          |> normalize_result()

        {:error, :llm_not_configured} = error ->
          error
      end
    end
  end

  @doc """
  The set of confirmed memory nodes that feed the bulletin, in the order the
  synthesizer prompt expects (durable kinds only).
  """
  def bulletin_input_nodes do
    Enum.flat_map(@bulletin_kinds, &list/1)
  end

  defp list(kind) do
    Atlas.Memory.list_nodes(scope: :global, kind: kind, limit: @recent_limit)
  end

  defp prompt(nodes) do
    sections =
      nodes
      |> Enum.group_by(& &1.kind)
      |> Enum.map(fn {kind, items} -> render_section(kind, items) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    """
    Synthesize the bulletin from these memory items. Keep names exact and
    omit empty groups.

    #{sections}
    """
  end

  defp render_section(_kind, []), do: nil

  defp render_section(kind, items) do
    header = kind |> Atom.to_string() |> String.upcase()

    body =
      items
      |> Enum.map_join("\n", fn %Node{body: body} -> "- #{body}" end)

    "#{header}:\n#{body}"
  end

  defp normalize_result({:ok, %{text: text}}) when is_binary(text), do: {:ok, text}
  defp normalize_result({:ok, text}) when is_binary(text), do: {:ok, text}
  defp normalize_result({:ok, _other}), do: {:error, :no_bulletin_text}
  defp normalize_result({:error, _reason} = error), do: error
end
