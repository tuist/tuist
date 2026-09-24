defmodule AtlasWeb.FeatureInterestsControllerTest do
  use AtlasWeb.ConnCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.Guardian
  alias Atlas.Repo

  test "manages feature interests and account context through the API", %{conn: conn} do
    {_session_conn, user} = log_in_user(conn)
    title = "Build capacity planning #{System.unique_integer([:positive])}"

    create_conn =
      user
      |> api_conn()
      |> post(~p"/api/feature-interests", %{"title" => title})

    assert %{"feature_interest" => %{"id" => interest_id, "title" => ^title, "interest_count" => 0}} =
             json_response(create_conn, 201)

    index_conn = user |> api_conn() |> get(~p"/api/feature-interests")

    assert %{"feature_interests" => interests, "count" => count} = json_response(index_conn, 200)
    assert count >= 1
    assert Enum.any?(interests, &(&1["id"] == interest_id))

    account = insert_account!()
    event = insert_event!(account)

    record_conn =
      user
      |> api_conn()
      |> post(
        ~p"/api/accounts/#{account.id}/timeline-events/#{event.id}/feature-interests",
        %{
          "title" => title,
          "summary" => "They need predictable release capacity.",
          "context" => "They currently operate their own runners and releases regularly queue."
        }
      )

    assert %{
             "feature_interest" => %{"id" => ^interest_id, "interest_count" => 1},
             "account_interest" => %{
               "id" => interest_account_id,
               "account_id" => account_id,
               "context" => "They currently operate their own runners and releases regularly queue."
             }
           } = json_response(record_conn, 201)

    assert account_id == account.id

    account_list_conn =
      user
      |> api_conn()
      |> get(~p"/api/accounts/#{account.id}/feature-interests")

    assert %{"feature_interests" => [%{"id" => ^interest_account_id}], "count" => 1} =
             json_response(account_list_conn, 200)

    context_conn =
      user
      |> api_conn()
      |> patch(
        ~p"/api/feature-interest-accounts/#{interest_account_id}",
        %{"context" => "Their current runner pool is costly and blocks release-week deployments."}
      )

    assert %{
             "account_interest" => %{
               "context" => "Their current runner pool is costly and blocks release-week deployments."
             }
           } = json_response(context_conn, 200)

    detail_conn = user |> api_conn() |> get(~p"/api/feature-interests/#{interest_id}")

    assert %{
             "feature_interest" => %{
               "accounts" => [
                 %{"id" => ^interest_account_id, "account_event_id" => event_id}
               ]
             }
           } = json_response(detail_conn, 200)

    assert event_id == event.id
  end

  test "requires an access token", %{conn: conn} do
    conn = get(conn, ~p"/api/feature-interests")

    assert %{"error" => "invalid_token"} = json_response(conn, 401)
  end

  defp api_conn(user) do
    {:ok, token, _claims} =
      Guardian.encode_and_sign(user, %{"scopes" => ["mcp"]}, token_type: "access_token")

    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
  end

  defp insert_account! do
    suffix = System.unique_integer([:positive])

    %Account{}
    |> Account.changeset(%{
      account_key: "account:feature-interest-api-#{suffix}",
      name: "Feature interest API account #{suffix}",
      segment: :customer
    })
    |> Repo.insert!()
  end

  defp insert_event!(account) do
    suffix = System.unique_integer([:positive])

    %Event{account_id: account.id}
    |> Event.changeset(%{
      external_id: "feature-interest-api-event-#{suffix}",
      source: "granola",
      kind: "meeting",
      title: "Feature request discussion",
      body: "The account described its current build capacity constraints.",
      occurred_at: ~U[2026-08-26 10:00:00Z]
    })
    |> Repo.insert!()
  end
end
