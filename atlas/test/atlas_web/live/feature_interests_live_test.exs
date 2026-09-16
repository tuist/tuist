defmodule AtlasWeb.FeatureInterestsLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.Repo

  test "creates a capability from the feature-interest registry", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    title = "Build capacity planning #{System.unique_integer([:positive])}"

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/feature-interests")

    assert has_element?(view, "#new-feature-interest-button")

    render_submit(view, "create_feature_interest", %{
      "feature_interest" => %{"title" => title}
    })

    [interest] = Accounts.list_feature_interests()
    assert interest.title == title
    assert_redirect(view, ~p"/commercial/sales/feature-interests/#{interest.id}")
  end

  test "shows every account interested in a requested capability and its event link", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    first_account = insert_account!("First account")
    second_account = insert_account!("Second account")
    first_event = insert_event!(first_account)
    second_event = insert_event!(second_account)

    assert {:ok, %{interest: interest}} =
             Accounts.record_feature_interest_from_event(
               first_event,
               %{title: "Remote build runners", summary: "They need runners for release builds."}
             )

    assert {:ok, _result} =
             Accounts.record_feature_interest_from_event(
               second_event,
               %{title: "remote BUILD runners", summary: "They need runners for pull request builds."}
             )

    {:ok, index_view, _html} = live(conn, ~p"/commercial/sales/feature-interests")

    assert has_element?(index_view, "#feature-interests-table", interest.title)
    assert has_element?(index_view, "#feature-interests-table", "2")

    {:ok, detail_view, _html} = live(conn, ~p"/commercial/sales/feature-interests/#{interest.id}")

    assert has_element?(detail_view, "[id^='feature-interest-account-link-']", first_account.name)
    assert has_element?(detail_view, "[id^='feature-interest-account-link-']", second_account.name)
    assert has_element?(detail_view, "[id^='feature-interest-source-'][href$='#timeline-event-#{first_event.id}']")
  end

  test "records an event-backed interest and edits its account note", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    account = insert_account!("Account detail")
    event = insert_event!(account)

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    assert has_element?(view, "#record-feature-interest-button")
    refute has_element?(view, "[id^='record-feature-interest-from-event-']")

    render_click(view, "open_feature_interest_modal")

    render_submit(view, "record_feature_interest", %{
      "feature_interest" => %{
        "title" => "Artifact retention",
        "summary" => "They need artifacts retained for audit reviews.",
        "notes" => "Security review is scheduled next week.",
        "account_event_id" => event.id
      }
    })

    [interest] = Accounts.list_feature_interests_for_account(account)
    [interest_account] = interest.accounts

    assert has_element?(view, "#account-feature-interest-#{interest.id}", interest.title)
    assert has_element?(view, "#account-feature-interest-source-#{interest.id}")
    assert has_element?(view, "#edit-feature-interest-notes-#{interest.id}")

    render_click(view, "open_feature_interest_notes_modal", %{"id" => interest_account.id})

    render_submit(view, "save_feature_interest_notes", %{
      "feature_interest_notes" => %{"notes" => "Security review now blocks the release plan."}
    })

    assert has_element?(
             view,
             "#account-feature-interest-#{interest.id}",
             "Security review now blocks the release plan."
           )
  end

  test "edits account context from a feature-interest detail", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    account = insert_account!("Feature detail account")
    event = insert_event!(account)

    assert {:ok, %{interest: interest}} =
             Accounts.record_feature_interest_from_event(
               event,
               %{title: "Remote build runners", summary: "They need runners for release builds."}
             )

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/feature-interests/#{interest.id}")
    interest = Accounts.get_feature_interest(interest.id)
    [interest_account] = interest.accounts

    assert has_element?(view, "#edit-feature-interest-context-#{interest_account.id}")

    render_click(view, "open_feature_interest_context_modal", %{"id" => interest_account.id})

    assert has_element?(view, "#feature-interest-context-modal")

    render_submit(view, "save_feature_interest_context", %{
      "feature_interest_context" => %{
        "notes" => "Currently uses a self-hosted runner pool with unpredictable capacity."
      }
    })

    assert has_element?(
             view,
             "#feature-interest-account-#{interest_account.id}",
             "Currently uses a self-hosted runner pool with unpredictable capacity."
           )
  end

  defp insert_account!(name) do
    suffix = System.unique_integer([:positive])

    %Account{}
    |> Account.changeset(%{
      account_key: "account:feature-interest-live-#{suffix}",
      name: name,
      segment: :customer
    })
    |> Repo.insert!()
  end

  defp insert_event!(account) do
    suffix = System.unique_integer([:positive])

    %Event{account_id: account.id}
    |> Event.changeset(%{
      external_id: "feature-interest-live-event-#{suffix}",
      source: "granola",
      kind: "meeting",
      title: "Feature request discussion",
      body: "Customer mentioned an important workflow need.",
      occurred_at: ~U[2026-08-26 10:00:00Z]
    })
    |> Repo.insert!()
  end
end
