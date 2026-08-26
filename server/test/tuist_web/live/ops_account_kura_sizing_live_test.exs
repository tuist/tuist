defmodule TuistWeb.OpsAccountKuraSizingLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Kura.ClaimProposal
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    stub(Accounts, :tuist_operator?, fn _ -> true end)
    %{conn: log_in_user(conn, user), user: user}
  end

  defp decision(account, attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert!(%ClaimProposal{
      account_id: account.id,
      region: "us-east",
      direction: :grow,
      current_claim_size: Keyword.get(attrs, :from, "8Gi"),
      recommended_claim_size: Keyword.get(attrs, :to, "16Gi"),
      evidence: %{"median_shed_age_seconds" => 1_800, "retention_floor_seconds" => 259_200},
      status: Keyword.get(attrs, :status, :applied),
      resolved_by: "automatic",
      resolved_at: now,
      inserted_at: DateTime.add(now, -Keyword.fetch!(attrs, :ago), :second)
    })
  end

  test "lists every decision on record", %{conn: conn, user: user} do
    decision(user.account, from: "8Gi", to: "16Gi", ago: 60)
    decision(user.account, from: "16Gi", to: "32Gi", ago: 30, status: :dismissed)

    {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}/kura/sizing")

    assert html =~ "Sizing decisions"
    assert html =~ "2 decisions"
    assert html =~ "8Gi → 16Gi"
    assert html =~ "16Gi → 32Gi"
    assert html =~ "dismissed"
  end

  test "pages through a history longer than one page", %{conn: conn, user: user} do
    for index <- 1..55, do: decision(user.account, to: "#{index}Gi", ago: index * 60)

    {:ok, lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}/kura/sizing")

    assert html =~ "55 decisions"
    assert html =~ "Page 1 of 2"
    # The 51st-newest is the first row of page two, so it must not be here yet.
    refute html =~ "8Gi → 51Gi"

    html = lv |> element("button", "Next") |> render_click()

    assert html =~ "Page 2 of 2"
    assert html =~ "8Gi → 51Gi"
  end

  test "says so when an account has no decisions", %{conn: conn, user: user} do
    {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}/kura/sizing")

    assert html =~ "Sizing has not decided anything for this account yet."
  end
end
