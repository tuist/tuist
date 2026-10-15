defmodule TuistWeb.Plugs.ReportActorPlugTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Projects.Project
  alias Tuist.ReportActor
  alias TuistWeb.Plugs.ReportActorPlug

  defp conn, do: Plug.Test.conn(:post, "/api/reports")

  test "claims cannot authenticate or create a user assignment" do
    conn = conn() |> put_req_header("x-tuist-actor-id", "admin") |> ReportActorPlug.call([])
    assert conn.halted
    assert conn.status == 401
    refute Map.has_key?(conn.assigns, :report_actor)
    refute Map.has_key?(conn.assigns, :current_user)
  end

  test "personal and OAuth identity come only from the authenticated individual" do
    user = %User{id: 7, account: %Account{id: 17, name: "verified"}}

    for {key, subject} <- [
          {:current_user, user},
          {:current_subject, %AuthenticatedAccount{account: %Account{id: 50}, scopes: [], issued_by: user}}
        ] do
      conn =
        conn()
        |> assign(key, subject)
        |> put_req_header("x-tuist-actor-id", "forged-person")
        |> ReportActorPlug.call([])

      assert ReportActor.attributes(conn) == %{
               actor_account_id: 17,
               claimed_actor_id: "forged-person",
               submission_auth: "token"
             }

      assert %{source: :verified, name: "verified", claimed_actor_id: "forged-person"} =
               ReportActorPlug.actor(conn)

      assert conn.assigns[key] == subject
    end
  end

  test "shared account and project credentials do not identify their creator or owner as an actor" do
    for {key, subject} <- [
          {:current_subject, %AuthenticatedAccount{account: %Account{id: 50}, scopes: []}},
          {:current_project, %Project{account: %Account{id: 50}}}
        ] do
      conn =
        conn()
        |> assign(key, subject)
        |> put_req_header("x-tuist-actor-id", "reported-person")
        |> ReportActorPlug.call([])

      assert %{actor_account_id: 0, claimed_actor_id: "reported-person", submission_auth: "token"} =
               ReportActor.attributes(conn)

      assert %{source: :reported, verified_account_handle: nil} = ReportActorPlug.actor(conn)
    end
  end

  test "absent, invalid, oversized, and duplicate claims do not replace verified identity" do
    user = %User{id: 7, account: %Account{id: 17, name: "verified"}}

    for headers <- [
          [],
          [{"x-tuist-actor-id", ""}],
          [{"x-tuist-actor-id", "a b"}],
          [{"x-tuist-actor-id", "é"}],
          [{"x-tuist-actor-id", String.duplicate("a", 129)}],
          [{"x-tuist-actor-id", "one"}, {"x-tuist-actor-id", "two"}]
        ] do
      conn = %{conn() | req_headers: headers} |> assign(:current_user, user) |> ReportActorPlug.call([])
      assert %{actor_account_id: 17, claimed_actor_id: "", submission_auth: "token"} = ReportActor.attributes(conn)
      assert %{source: :verified, name: "verified"} = ReportActorPlug.actor(conn)
    end
  end
end
