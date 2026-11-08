defmodule AtlasWeb.LabelsControllerTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Authorization.UserRole
  alias Atlas.Labels
  alias Atlas.Labels.Job
  alias Atlas.Labels.Session
  alias Atlas.MCP.Tools.ManageLabelSession
  alias Atlas.Repo

  setup %{conn: conn} do
    {browser, user} = log_in_user(conn, %{scopes: ["assets:write"]})
    mcp = build_conn() |> assign(:current_user, user) |> assign(:audit_interface, "mcp")
    %{browser: browser, user: user, mcp: mcp}
  end

  defp api(token, method, path, body \\ %{}) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp mcp(conn, action, args \\ %{}) do
    assert %{"structuredContent" => %{"result" => result}} =
             ManageLabelSession.call(conn, Map.put(args, "action", action))

    result
  end

  defp session(conn) do
    mcp(conn, "create")
  end

  defp report do
    %{
      "clientId" => "test-relay-1234",
      "connected" => true,
      "model" => "M211",
      "name" => "M211-#{System.unique_integer([:positive])}",
      "supply" => "M21-750-427",
      "zoneDimensions" => [%{"Width" => "38.1", "Height" => "10", "Type" => "Printable"}],
      "cutReady" => true
    }
  end

  test "MCP preparation is owner scoped, atomic and distinct from relay transport", c do
    s = session(c.mcp)
    relay = "/api/labels/relay/sessions/#{s["id"]}"
    {other_browser, other} = log_in_user(build_conn(), %{scopes: ["assets:write"]})
    other_mcp = assign(c.mcp, :current_user, other)

    assert %{"isError" => true} =
             ManageLabelSession.call(other_mcp, %{"action" => "status", "session_id" => s["id"]})

    assert api("invalid", :get, relay).status == 401

    assert %{"isError" => true} =
             ManageLabelSession.call(c.mcp, %{
               "action" => "submit",
               "session_id" => s["id"],
               "items" => [%{"text" => "RACK-09"}, %{"text" => ""}]
             })

    assert mcp(c.mcp, "status", %{"session_id" => s["id"]})["jobs"] == []

    assert mcp(c.mcp, "submit", %{
             "session_id" => s["id"],
             "items" => [%{"text" => "SW02 & <UPLINK>"}],
             "width_mm" => 38.1,
             "height_mm" => 10
           }) == %{"queued" => 1, "state" => "preview-only"}

    [job] = mcp(c.mcp, "status", %{"session_id" => s["id"]})["jobs"]
    assert job["state"] == "preview-only"
    preview = mcp(c.mcp, "preview", %{"session_id" => s["id"], "job_id" => job["id"]})
    png = Base.decode64!(preview["png"])
    image_path = "/operations/labels/#{s["id"]}/jobs/#{job["id"]}/preview"
    image = get(c.browser, image_path)
    assert image.resp_body == png
    assert <<137, 80, 78, 71, 13, 10, 26, 10, 13::32, "IHDR", 305::32, 80::32, _::binary>> = image.resp_body
    assert api(s["relayToken"], :get, relay <> "/jobs/#{job["id"]}.png").resp_body == image.resp_body
    assert get(other_browser, image_path).status == 404
    assert get_resp_header(image, "cache-control") == ["no-store"]

    assert mcp(c.mcp, "submit", %{"session_id" => s["id"], "items" => [%{"png" => preview["png"]}]})["queued"] == 1

    {:ok, view, _} = live(c.browser, "/operations/labels/#{s["id"]}")
    assert has_element?(view, "#label-relay")
    refute has_element?(view, "a[href='/operations/labels']")
    refute has_element?(view, "#labels form")

    assert byte_size(Repo.get!(Session, s["id"]).relay_token_hash) == 32
  end

  test "only owner dashboard approval can queue output; claims survive callers and cannot replay", c do
    s = session(c.mcp)
    relay = "/api/labels/relay/sessions/#{s["id"]}"
    report = report()
    assert api(s["relayToken"], :post, relay <> "/relay", report).status == 200
    mcp(c.mcp, "submit", %{"session_id" => s["id"], "items" => [%{"text" => "ASYMMETRIC-09"}]})
    [job] = mcp(c.mcp, "status", %{"session_id" => s["id"]})["jobs"]
    assert api(s["relayToken"], :post, relay <> "/jobs/#{job["id"]}/claim", report).status == 409
    pending = mcp(c.mcp, "request_print", %{"session_id" => s["id"], "job_id" => job["id"]})
    assert pending["state"] == "awaiting-approval"
    assert {:error, 400, _} = Labels.request(c.user, :approve, s["id"], %{"jobId" => job["id"]}, "mcp")
    {other_browser, _} = log_in_user(build_conn(), %{scopes: ["assets:write"]})
    {:ok, other_view, _} = live(other_browser, "/operations/labels/#{s["id"]}/jobs/#{job["id"]}/approval")
    refute has_element?(other_view, "#approve-label")
    {:ok, view, _} = live(c.browser, "/operations/labels/#{s["id"]}/jobs/#{job["id"]}/approval")
    assert has_element?(view, "#label-preview")
    assert has_element?(view, "#approve-label:not([disabled])")
    view |> element("#approve-label") |> render_click()
    assert Repo.get!(Job, job["id"]).state == "queued"
    assert has_element?(view, "#approve-label[disabled]")

    assert api(s["relayToken"], :post, relay <> "/jobs/#{job["id"]}/claim", %{report | "clientId" => "different-relay"}).status ==
             409

    claim = api(s["relayToken"], :post, relay <> "/jobs/#{job["id"]}/claim", report) |> json_response(200)
    assert claim["state"] == "dispatched"
    # Fresh request reads PostgreSQL, not a process-local queue or session cache.
    assert [%{"state" => "dispatched"}] = mcp(c.mcp, "status", %{"session_id" => s["id"]})["jobs"]
    assert api(s["relayToken"], :post, relay <> "/jobs/#{job["id"]}/claim", report).status == 409

    assert api(s["relayToken"], :post, relay <> "/jobs/#{job["id"]}/result", Map.put(report, "success", false)).status ==
             200

    assert Repo.get!(Job, job["id"]).state == "uncertain"

    assert mcp(c.mcp, "request_print", %{"session_id" => s["id"], "job_id" => job["id"]})["state"] ==
             "uncertain"

    assert %{"isError" => true} = ManageLabelSession.call(c.mcp, %{"action" => "request_cut", "session_id" => s["id"]})
  end

  test "sizing, relay lease and expiry changes block approval and dispatch", c do
    s = session(c.mcp)
    r = report()
    id = s["id"]
    token = s["relayToken"]
    assert {:ok, _} = Labels.request(c.user, :submit, id, %{"items" => [%{"text" => "RACK-09"}]})
    {:ok, %{"jobs" => [job]}} = Labels.request(c.user, :status, id)
    assert {:error, 409, _} = Labels.request(c.user, :print, id, %{"jobId" => job["id"]})
    assert {:ok, _} = Labels.relay(:relay, id, token, %{r | "zoneDimensions" => [%{"Width" => "0", "Height" => "10"}]})
    assert {:error, 409, _} = Labels.request(c.user, :print, id, %{"jobId" => job["id"]})
    assert {:ok, _} = Labels.relay(:relay, id, token, r)
    assert {:error, 409, _} = Labels.relay(:relay, id, token, %{r | "clientId" => "another-active-relay"})
    assert {:ok, _} = Labels.request(c.user, :print, id, %{"jobId" => job["id"]})
    assert {:ok, _} = Labels.relay(:relay, id, token, %{r | "zoneDimensions" => [%{"Width" => "45", "Height" => "10"}]})
    assert {:error, 409, _} = Labels.request(c.user, :approve, id, %{"jobId" => job["id"]}, "dashboard")
    assert {:ok, _} = Labels.relay(:relay, id, token, r)
    assert {:ok, _} = Labels.request(c.user, :approve, id, %{"jobId" => job["id"]}, "dashboard")
    j = Repo.get!(Job, job["id"])
    Repo.update!(Ecto.Changeset.change(j, data: Map.put(j.data, "approvalExpiresAt", 0)))
    assert {:error, 409, _} = Labels.relay(:claim, id, token, Map.put(r, "jobId", job["id"]))
    Repo.update!(Ecto.Changeset.change(Repo.get!(Session, id), expires_at: DateTime.add(DateTime.utc_now(), -1)))
    assert {:error, 404, _} = Labels.request(c.user, :status, id)
    assert {:error, 404, _} = Labels.relay(:status, id, token)
  end

  test "a separate cut needs its own approval after SDK-confirmed print", c do
    {:ok, s} = Labels.create(c.user, "api")
    id = s["id"]
    token = s["relayToken"]
    r = report()
    {:ok, _} = Labels.relay(:relay, id, token, r)
    {:ok, _} = Labels.request(c.user, :submit, id, %{"items" => [%{"text" => "CUT-09"}]})
    {:ok, %{"jobs" => [j]}} = Labels.request(c.user, :status, id)
    data = Map.put(r, "jobId", j["id"])
    {:ok, _} = Labels.request(c.user, :print, id, data)
    {:ok, _} = Labels.request(c.user, :approve, id, data, "dashboard")
    {:ok, _} = Labels.relay(:claim, id, token, data)
    {:ok, _} = Labels.relay(:result, id, token, Map.put(data, "success", true))
    {:ok, cut} = Labels.request(c.user, :cut, id)
    assert cut["action"] == "cut"
    assert cut["state"] == "awaiting-approval"
    cut_data = Map.put(r, "jobId", cut["id"])
    assert {:error, 409, _} = Labels.relay(:claim, id, token, cut_data)
    {:ok, view, _} = live(c.browser, "/operations/labels/#{id}/jobs/#{cut["id"]}/approval")
    refute has_element?(view, "#label-preview")
    view |> element("#approve-label") |> render_click()
    assert {:ok, %{"action" => "cut", "state" => "dispatched"}} = Labels.relay(:claim, id, token, cut_data)
    assert {:error, 409, _} = Labels.relay(:claim, id, token, cut_data)
  end

  test "MCP is personal, schema checked and cannot approve", c do
    import Ecto.Query

    conn = build_conn() |> assign(:current_user, c.user) |> assign(:audit_interface, "mcp")

    assert %{"structuredContent" => %{"result" => %{"relayUrl" => url}}} =
             ManageLabelSession.call(conn, %{"action" => "create"})

    assert url =~ "/operations/labels/"
    assert %{"isError" => true} = ManageLabelSession.call(conn, %{"action" => "approve"})

    assert %{"isError" => true} =
             ManageLabelSession.call(assign(conn, :mcp_claims, %{"slack_agent" => false}), %{"action" => "create"})

    {_, reader} = log_in_user(build_conn(), %{scopes: ["assets:read"]})
    assert {:error, 403, _} = Labels.create(reader, "api")
    {:ok, s} = Labels.create(c.user, "api")
    # Owner permission is reloaded on relay mutations, not captured at pairing.
    Repo.delete_all(from role in UserRole, where: role.user_id == ^c.user.id)
    assert {:error, 403, _} = Labels.relay(:relay, s["id"], s["relayToken"], report())
  end
end
