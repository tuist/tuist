defmodule TuistOpsWeb.GrantControllerTest do
  use TuistOpsWeb.ConnCase, async: true
  use Mimic

  alias TuistOps.ProjectAccess.Request
  alias TuistOps.Repo

  setup :verify_on_exit!

  setup do
    stub(TuistOps.Environment, :dev_operator_email, fn -> "marek@tuist.dev" end)
    :ok
  end

  describe "GET /grants/:id/pending" do
    test "a pending request reloads itself (Refresh header) and shows the waiting state", %{
      conn: conn
    } do
      req = insert_request!(%{status: "pending"})
      conn = get(conn, "/grants/#{req.id}/pending")

      assert get_resp_header(conn, "refresh") == ["3"]
      assert html_response(conn, 200) =~ "Waiting"
    end

    test "a denied request is terminal — no Refresh header", %{conn: conn} do
      req = insert_request!(%{status: "denied"})
      conn = get(conn, "/grants/#{req.id}/pending")

      assert get_resp_header(conn, "refresh") == []
      assert html_response(conn, 200) =~ "Request denied"
    end

    test "an expired request is terminal", %{conn: conn} do
      req = insert_request!(%{status: "expired"})
      conn = get(conn, "/grants/#{req.id}/pending")

      assert get_resp_header(conn, "refresh") == []
      assert html_response(conn, 200) =~ "Request expired"
    end

    test "a request owned by a different operator is forbidden", %{conn: conn} do
      req = insert_request!(%{requester_email: "someone-else@tuist.dev"})
      conn = get(conn, "/grants/#{req.id}/pending")

      assert conn.status == 403
    end
  end

  defp insert_request!(overrides) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    %{
      requester_email: "marek@tuist.dev",
      account_handle: "acme",
      tier: "admin",
      reason: "rotate leaked credentials",
      return_to: "https://tuist.dev/acme/app",
      ttl_seconds: 1800,
      slack_channel_id: "C_TEST",
      status: "pending",
      expires_at: DateTime.add(now, 600, :second)
    }
    |> Map.merge(overrides)
    |> Request.create_changeset()
    |> Repo.insert!()
  end
end
