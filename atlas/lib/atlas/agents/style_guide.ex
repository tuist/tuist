defmodule Atlas.Agents.StyleGuide do
  @moduledoc """
  Cross-cutting prose rules every Atlas agent must follow when writing
  user-facing text.

  Each `use Condukt` agent appends `prose_rules/0` to its `system_prompt/0`
  so the rules are inherited consistently. Add agent-specific guidance to
  the agent's own prompt.
  """

  @prose_rules """
  Style rules:
  - Never use em dashes. Use commas, colons, hyphens, or sentence breaks.
  """

  @doc """
  Returns the shared prose rules block. Append it to every agent's
  `system_prompt/0` so the rules are consistently applied.
  """
  def prose_rules, do: @prose_rules
end
