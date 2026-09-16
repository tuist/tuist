defmodule Atlas.Accounts.OverviewSummary do
  @moduledoc false

  import Ecto.Query

  alias Atlas.Accounts.Agents.OverviewSummaryAgent
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.Query
  alias Atlas.Audit
  alias Atlas.Repo
  alias Atlas.Search

  @summary_event_limit 30

  def refresh(account_id, opts \\ []) do
    summarize = Keyword.get(opts, :summarize, &OverviewSummaryAgent.summarize/1)

    case Query.get_account(account_id) do
      nil ->
        {:error, :not_found}

      account ->
        account = preload_summary_context(account)

        with {:ok, summary} <- summarize.(account) do
          result =
            account
            |> Ecto.Changeset.change(%{
              overview_summary: summary,
              overview_summary_generated_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })
            |> Repo.update()

          case result do
            {:ok, updated_account} = success ->
              Search.index_account_overview_summary(updated_account)

              Audit.record(
                "account.overview_summary_refreshed",
                %{
                  target_type: "account",
                  target_id: updated_account.id,
                  target_label: updated_account.name,
                  metadata: %{
                    "path" => "/sales/accounts/#{updated_account.id}",
                    "generated_at" => updated_account.overview_summary_generated_at,
                    "summary_length" => String.length(summary)
                  }
                }
              )

              success

            error ->
              error
          end
        end
    end
  end

  defp preload_summary_context(account) do
    Repo.preload(account,
      events:
        {from(event in Event,
           order_by: [desc: event.occurred_at, desc: event.inserted_at],
           limit: @summary_event_limit
         ), [:author]}
    )
  end
end
