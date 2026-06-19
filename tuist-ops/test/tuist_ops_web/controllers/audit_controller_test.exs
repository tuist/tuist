defmodule TuistOpsWeb.AuditControllerTest do
  use TuistOpsWeb.ConnCase, async: true
  use Mimic

  setup :verify_on_exit!

  test "401s without a Pomerium-verified identity", %{conn: conn} do
    stub(TuistOps.Environment, :dev_operator_email, fn -> nil end)
    conn = get(conn, "/audit?section=cluster")
    assert conn.status == 401
  end

  test "renders the audit trail with a verified identity", %{conn: conn} do
    stub(TuistOps.Environment, :dev_operator_email, fn -> "marek@tuist.dev" end)
    conn = get(conn, "/audit?section=cluster")
    assert html_response(conn, 200) =~ "Audit trail"
  end
end
