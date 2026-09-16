defmodule AtlasWeb.AccountOverviewSummaryLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Accounts.Account
  alias Atlas.Repo

  test "renders the persisted overview summary markdown", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "overview-summary@example.com"})

    account =
      insert_account!(%{
        account_key: "enterprise:overview-summary",
        name: "Overview Summary",
        segment: :customer
      })

    account
    |> Ecto.Changeset.change(%{
      overview_summary:
        "**Overview Summary** is active with a renewal follow-up in progress.\n\n- Confirm procurement timeline.",
      overview_summary_generated_at: ~U[2026-05-11 09:30:00Z]
    })
    |> Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/sales/accounts/#{account.id}")

    assert has_element?(view, "#refresh-overview-summary-button", "Summarize")
    assert has_element?(view, "#overview-metadata-grid")
    assert has_element?(view, "#overview-summary [data-part='metadata-title']", "Summary")
    assert has_element?(view, "#overview-summary [data-part='overview-summary-time']", "Updated")
    assert has_element?(view, "[data-part='overview-summary-body'] strong", "Overview Summary")
    assert has_element?(view, "[data-part='overview-summary-body'] li", "Confirm procurement timeline.")
  end

  test "shows an error when manual summarization is unavailable", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "overview-summary-error@example.com"})

    account =
      insert_account!(%{
        account_key: "enterprise:overview-summary-error",
        name: "Overview Summary Error",
        segment: :customer
      })

    {:ok, view, _html} = live(conn, ~p"/sales/accounts/#{account.id}")

    view
    |> element("#refresh-overview-summary-button")
    |> render_click()

    assert has_element?(view, "#overview-summary-error", "Language model is not configured")
  end

  defp insert_account!(attrs) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account",
      segment: :lead
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
