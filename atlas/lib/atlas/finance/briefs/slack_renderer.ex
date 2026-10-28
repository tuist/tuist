defmodule Atlas.Finance.Briefs.SlackRenderer do
  @moduledoc false

  # Slack sections allow 3,000 characters. Pack escaped words rather than
  # slicing the final markup, which can break entities or bold delimiters.
  @text_limit 2800

  def build_blocks(brief) do
    report = brief.report
    period_end = brief.period_end |> DateTime.add(-1, :second) |> DateTime.to_date()

    [
      %{
        "type" => "header",
        "text" => %{"type" => "plain_text", "text" => String.slice(brief.headline, 0, 150)}
      },
      %{
        "type" => "context",
        "elements" => [
          %{
            "type" => "plain_text",
            "text" => "#{DateTime.to_date(brief.period_start)} to #{period_end}"
          }
        ]
      }
    ] ++
      fallback_notice(report) ++
      prose_blocks(report["intro"]) ++
      findings("Key factors driving the numbers", report["drivers"]) ++
      findings("What to watch", report["concerns"]) ++
      next_steps(report["next_steps"]) ++
      [
        %{"type" => "divider"},
        section("<#{AtlasWeb.Endpoint.url()}/commercial/finance|Explore the finance dashboard>")
      ]
  end

  defp fallback_notice(%{"generation_mode" => "deterministic_fallback"}) do
    [section("_Automated snapshot: agent analysis was unavailable for this update._")]
  end

  defp fallback_notice(_report), do: []

  defp findings(_heading, findings) when findings in [nil, []], do: []

  defp findings(heading, findings) do
    [section("*#{heading}*")] ++
      Enum.flat_map(findings, fn finding ->
        [section("*#{finding["title"] |> String.slice(0, 120) |> plain_text()}*")] ++
          prose_blocks(finding["detail"])
      end)
  end

  defp next_steps(steps) when steps in [nil, []], do: []

  defp next_steps(steps) do
    [section("*Recommended next steps*")] ++ Enum.flat_map(steps, &prose_blocks("• " <> &1))
  end

  defp prose_blocks(text) do
    ~r/\n\s*\n|[^\s]+/u
    |> Regex.scan(text)
    |> List.flatten()
    |> Enum.flat_map(fn token ->
      if String.starts_with?(token, "\n"), do: ["\n\n"], else: split_word(token)
    end)
    |> Enum.map(&plain_text/1)
    |> Enum.reduce([], &pack_word/2)
    |> Enum.reverse()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&section/1)
  end

  # Split before escaping so an entity always stays intact. Each original
  # character expands to at most six characters when escaped.
  defp split_word(word), do: Regex.scan(~r/.{1,400}/us, word) |> List.flatten()

  defp pack_word(word, [current | rest]) do
    separator = if word == "\n\n" or String.ends_with?(current, "\n\n"), do: "", else: " "

    if String.length(current) + String.length(word) + String.length(separator) <= @text_limit,
      do: [current <> separator <> word | rest],
      else: [word, current | rest]
  end

  defp pack_word(word, []), do: [word]

  # The agent supplies prose, while this renderer owns the Slack syntax.
  # Neutralize markers in merchant names too, such as Mol*Vendor.
  defp plain_text(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("*", "∗")
    |> String.replace("_", "＿")
    |> String.replace("~", "∼")
    |> String.replace("`", "ˋ")
  end

  defp section(text), do: %{"type" => "section", "text" => %{"type" => "mrkdwn", "text" => text}}
end
