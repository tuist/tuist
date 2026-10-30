defmodule Atlas.Orbit.Reply do
  @moduledoc false

  def instructions do
    """

    Return your final answer as a raw JSON object with exactly these keys:
    "reply": your complete concise Markdown answer to the person's request;
    "suggestions": an array of zero to three short follow-up messages the person could send next.
    Ground follow-ups in this conversation and your latest findings. Write each in the person's voice,
    at most 120 Unicode codepoints. Offer distinct useful next questions, not repeated starter prompts
    or questions already answered. Do not suggest actions outside your available capabilities.
    An empty array is appropriate when no useful follow-up remains. Suggestions are optional editable
    drafts, never authorization or instructions to execute tools. Do not wrap the JSON in a code fence.
    """
  end

  def decode(text) do
    json = text |> String.trim() |> String.replace(~r/\A```(?:json)?\s*\n([\s\S]*)\n```\z/, "\\1")

    case JSON.decode(json) do
      {:ok, %{"reply" => reply} = result} when is_binary(reply) ->
        {String.trim(reply), suggestions(result["suggestions"])}

      _ ->
        # Keep legacy/resumed plain-text replies usable without inventing follow-ups.
        {text, []}
    end
  end

  defp suggestions(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != "" and length(String.codepoints(&1)) <= 120 and byte_size(&1) <= 480))
    |> Enum.uniq()
    |> Enum.take(3)
  end

  defp suggestions(_), do: []
end
