defmodule Atlas.Accounts.Agents.OverviewSummaryAgent do
  @moduledoc """
  Generates a concise account overview from the account timeline.
  """

  use Condukt

  alias Atlas.Agents.Sessions
  alias Atlas.Agents.StyleGuide
  alias Atlas.LLMs.Runner

  @impl true
  def tools, do: []

  @impl true
  def system_prompt do
    """
    You write concise account overview summaries for a sales and customer
    operations workspace.

    Analyze the account profile and all timeline events. Summarize where the
    relationship currently stands, including lifecycle, recent activity,
    blockers, renewal or commercial signals, customer sentiment, and concrete
    next steps when they are present.

    Write the summary in Markdown. Prefer 2-4 concise sentences in short
    paragraphs, and when concrete next steps are present, add them as a short
    bullet list after the prose. Be factual and grounded only in the supplied
    events. Do not invent facts. If there is not enough activity to assess the
    account, say that plainly.

    #{StyleGuide.prose_rules()}
    """
  end

  def summarize(account) do
    with {:ok, llm} <- Runner.fetch_config() do
      Sessions.run(
        __MODULE__,
        build_prompt(account),
        Runner.client_opts(llm) ++ [max_turns: 1, account_id: account.id]
      )
    end
  end

  defp build_prompt(account) do
    """
    Draft the current overview summary for this account.

    Account:
    #{account_context(account)}

    Timeline events:
    #{events_context(account.events)}
    """
  end

  defp account_context(account) do
    [
      {"Name", account.name},
      {"Lifecycle", account.segment},
      {"Description", account.description},
      {"Current value", account.current_value},
      {"Currency", account.currency},
      {"Next renewal", account.next_renewal_date},
      {"Primary domain", account.primary_domain}
    ]
    |> Enum.map_join("\n", fn {label, value} -> "- #{label}: #{format_value(value)}" end)
  end

  defp events_context([]), do: "No timeline events captured."

  defp events_context(events) do
    events
    |> Enum.reverse()
    |> Enum.map_join("\n\n", &event_context/1)
  end

  defp event_context(event) do
    """
    - Date: #{format_value(event.occurred_at)}
      Source: #{format_value(event.source)}
      Kind: #{format_value(event.kind)}
      Title: #{format_value(event.title)}
      Body: #{format_value(event.body)}
    """
  end

  defp format_value(nil), do: "-"
  defp format_value(%Date{} = date), do: Date.to_iso8601(date)
  defp format_value(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_value(%Decimal{} = decimal), do: Decimal.to_string(decimal, :normal)
  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value), do: to_string(value)
end
