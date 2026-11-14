defmodule AtlasWeb.LabelsControllerTest do
  use AtlasWeb.ConnCase, async: true

  import Ecto.Query
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

  test "sessions accept more than 100 labels while retaining submission and batch limits", c do
    {id, _token, _r, [first]} = connected_session(c, ["LABEL-1"])
    job = Repo.get!(Job, first)

    # Fill the session to the old lifetime cap without rendering the same fixture 99 times.
    Repo.insert_all(
      Job,
      for _ <- 2..100 do
        %{
          id: Atlas.UUIDv7.generate(),
          session_id: id,
          action: job.action,
          state: job.state,
          png: job.png,
          data: job.data,
          inserted_at: job.inserted_at,
          updated_at: job.updated_at
        }
      end
    )

    assert mcp(c.mcp, "submit", %{"session_id" => id, "items" => [%{"text" => "LABEL-101"}]}) ==
             %{"queued" => 1, "state" => "preview-only"}

    status = mcp(c.mcp, "status", %{"session_id" => id})
    assert length(status["jobs"]) == 101
    assert status["counts"] == %{"preview-only" => 101}
    assert List.last(status["jobs"])["title"] == "LABEL-101"

    assert {:error, 400, _} = Labels.request(c.user, :submit, id, %{"items" => []})

    assert {:error, 400, _} =
             Labels.request(c.user, :submit, id, %{"items" => List.duplicate(%{"text" => "TOO MANY"}, 51)})

    assert {:error, 400, _} = Labels.request(c.user, :print, id, %{"approval" => true})
    assert {:error, 400, _} = Labels.request(c.user, :print, id, %{})

    assert {:ok, %{"count" => 1, "state" => "queued"}} =
             Labels.request(c.user, :print, id, %{"jobIds" => [List.last(status["jobs"])["id"]]})
  end

  test "connected reports keep the same relay capability alive past its original deadline", c do
    Mimic.stub(DateTime, :utc_now, fn -> ~U[2026-11-10 08:05:00.000000Z] end)
    s = session(c.mcp)
    path = "/api/labels/relay/sessions/#{s["id"]}"
    original_expiry = DateTime.to_unix(~U[2026-11-10 16:05:00Z], :millisecond)
    assert s["expiresAt"] == original_expiry
    r = report()

    Mimic.stub(DateTime, :utc_now, fn -> ~U[2026-11-10 15:05:00.000000Z] end)
    assert api(s["relayToken"], :post, path <> "/relay", r).status == 200

    Mimic.stub(DateTime, :utc_now, fn -> ~U[2026-11-10 16:05:00.000000Z] end)
    status = json_response(api(s["relayToken"], :get, path), 200)
    assert status["expiresAt"] == DateTime.to_unix(~U[2026-11-10 23:05:00Z], :millisecond)

    # Exact deadline is expired: neither a late report nor the owner can revive it.
    Mimic.stub(DateTime, :utc_now, fn -> ~U[2026-11-10 23:05:00.000000Z] end)
    assert api(s["relayToken"], :post, path <> "/relay", r).status == 404
    assert api(s["relayToken"], :get, path).status == 404
    assert {:error, 404, _} = Labels.request(c.user, :status, s["id"])
  end

  test "successful agent activity and explicit owner actions renew the idle deadline", c do
    Mimic.stub(DateTime, :utc_now, fn -> ~U[2026-11-10 08:05:00.000000Z] end)
    s = session(c.mcp)

    Mimic.stub(DateTime, :utc_now, fn -> ~U[2026-11-10 15:05:00.000000Z] end)
    status = mcp(c.mcp, "status", %{"session_id" => s["id"]})
    assert status["expiresAt"] == DateTime.to_unix(~U[2026-11-10 23:05:00Z], :millisecond)

    Mimic.stub(DateTime, :utc_now, fn -> ~U[2026-11-10 22:05:00.000000Z] end)
    assert {:ok, %{"relayToken" => token}} = Labels.request(c.user, :relay_token, s["id"], %{}, "dashboard")
    assert {:ok, status} = Labels.relay(:status, s["id"], token)
    assert status["expiresAt"] == DateTime.to_unix(~U[2026-11-11 06:05:00Z], :millisecond)
    assert {:error, 401, _} = Labels.relay(:status, s["id"], s["relayToken"])
  end

  test "passive polling, disconnected reports and rejected requests do not renew sessions", c do
    {_, other} = log_in_user(build_conn(), %{scopes: ["assets:write"]})
    Mimic.stub(DateTime, :utc_now, fn -> ~U[2026-11-10 08:05:00.000000Z] end)
    {id, token, r, [job]} = connected_session(c, ["IDLE"])
    expiry = DateTime.to_unix(~U[2026-11-10 16:05:00Z], :millisecond)

    Mimic.stub(DateTime, :utc_now, fn -> ~U[2026-11-10 15:05:00.000000Z] end)
    assert {:ok, _} = Labels.relay(:relay, id, token, %{r | "connected" => false})
    assert {:ok, _} = Labels.relay(:image, id, token, %{"jobId" => job})
    assert {:ok, _} = Labels.request(c.user, :image, id, %{"jobId" => job}, "dashboard")
    assert {:ok, %{"expiresAt" => ^expiry}} = Labels.request(c.user, :status, id, %{}, "dashboard")
    assert {:error, 404, _} = Labels.request(other, :status, id)
    assert {:error, 401, _} = Labels.relay(:relay, id, "invalid", r)
    assert {:error, 400, _} = Labels.relay(:relay, id, token, %{r | "clientId" => "invalid"})
    assert {:error, 409, _} = Labels.request(c.user, :print, id, %{}, "mcp")
    assert {:ok, %{"expiresAt" => ^expiry}} = Labels.relay(:status, id, token)

    Mimic.stub(DateTime, :utc_now, fn -> ~U[2026-11-10 16:05:00.000000Z] end)
    assert {:error, 404, _} = Labels.relay(:relay, id, token, r)
    assert {:error, 404, _} = Labels.request(c.user, :status, id)
  end

  defp connected_session(c, texts) do
    {:ok, s} = Labels.create(c.user, "api")
    r = report()
    {:ok, _} = Labels.relay(:relay, s["id"], s["relayToken"], r)
    {:ok, _} = Labels.request(c.user, :submit, s["id"], %{"items" => Enum.map(texts, &%{"text" => &1})})
    {:ok, %{"jobs" => jobs}} = Labels.request(c.user, :status, s["id"])
    {s["id"], s["relayToken"], r, Enum.map(jobs, & &1["id"])}
  end

  defp claim(id, token, r, job), do: Labels.relay(:claim, id, token, Map.put(r, "jobId", job))

  defp finish(id, token, r, job, result),
    do: Labels.relay(:result, id, token, r |> Map.put("jobId", job) |> Map.merge(result))

  defp states(id),
    do: Enum.map(Repo.all(from(j in Job, where: j.session_id == ^id, order_by: j.inserted_at)), & &1.state)

  test "the agent prints a whole batch directly, in its chosen order, cutting after each label", c do
    {id, token, r, [a, b, cc]} = connected_session(c, ~w(R02-A R02-B R02-C))

    batch = mcp(c.mcp, "print", %{"session_id" => id, "job_ids" => [cc, a, b]})
    assert %{"count" => 3, "state" => "queued", "cut" => true, "approvalUrl" => nil} = batch
    assert Enum.map(batch["jobs"], & &1["title"]) == ~w(R02-C R02-A R02-B)

    # Order is enforced by PostgreSQL, not by the relay: A cannot go before C is confirmed.
    assert {:error, 409, _} = claim(id, token, r, a)
    assert {:ok, %{"state" => "dispatched", "cut" => true}} = claim(id, token, r, cc)
    # One operation in flight at a time, even within the batch.
    assert {:error, 409, _} = claim(id, token, r, a)
    assert {:ok, _} = finish(id, token, r, cc, %{"success" => true, "cutSuccess" => true})
    assert {:ok, _} = claim(id, token, r, a)
    assert {:ok, _} = finish(id, token, r, a, %{"success" => true, "cutSuccess" => true})
    assert {:ok, _} = claim(id, token, r, b)
    assert {:ok, _} = finish(id, token, r, b, %{"success" => true, "cutSuccess" => true})
    # A consumed claim never returns to the queue.
    assert {:error, 409, _} = claim(id, token, r, b)

    status = mcp(c.mcp, "status", %{"session_id" => id})
    assert status["counts"] == %{"sdk-confirmed" => 3}
    assert Enum.all?(status["jobs"], &(&1["printResult"] == "sdk-confirmed" and &1["cutResult"] == "sdk-confirmed"))

    # Printed labels are not printed again; reprinting needs a new submission.
    assert %{"isError" => true} = ManageLabelSession.call(c.mcp, %{"action" => "print", "session_id" => id})
  end

  test "unreviewed output is one batch of at most 20 labels at a time", c do
    {id, _token, _r, ids} = connected_session(c, for(n <- 1..21, do: "R02-#{n}"))
    {first, [last]} = Enum.split(ids, 20)

    assert {:error, 400, _} = Labels.request(c.user, :print, id, %{}, "mcp")
    assert states(id) == List.duplicate("preview-only", 21)

    assert {:ok, %{"state" => "queued", "count" => 20}} =
             Labels.request(c.user, :print, id, %{"jobIds" => first}, "mcp")

    # No further unreviewed output while that batch is queued or printing; review still works.
    assert {:error, 409, _} = Labels.request(c.user, :print, id, %{"jobIds" => [last]}, "mcp")

    assert {:ok, %{"state" => "awaiting-approval"}} =
             Labels.request(c.user, :print, id, %{"jobIds" => [last], "approval" => true}, "mcp")
  end

  test "an uncertain label stops the rest of the batch and reports each label honestly", c do
    {id, token, r, [a, b, cc]} = connected_session(c, ~w(R02-A R02-B R02-C))
    assert {:ok, %{"count" => 3}} = Labels.request(c.user, :print, id, %{}, "mcp")

    assert {:ok, _} = claim(id, token, r, a)
    assert {:ok, _} = finish(id, token, r, a, %{"success" => true, "cutSuccess" => true})
    assert {:ok, _} = claim(id, token, r, b)
    # Printed but the cut failed: the label is uncertain, not confirmed.
    assert {:ok, %{"state" => "uncertain", "printResult" => "sdk-confirmed", "cutResult" => "uncertain"}} =
             finish(id, token, r, b, %{"success" => true, "cutSuccess" => false})

    assert states(id) == ~w(sdk-confirmed uncertain preview-only)
    assert {:error, 409, _} = claim(id, token, r, cc)
    assert Repo.get!(Job, cc).data["note"] =~ "R02-B"

    # The unprinted label can be deliberately queued again; the uncertain one cannot.
    assert {:error, 409, _} = Labels.request(c.user, :print, id, %{"jobIds" => [b]}, "mcp")
    assert {:ok, %{"count" => 1}} = Labels.request(c.user, :print, id, %{"jobIds" => [cc], "cut" => false}, "mcp")
    assert {:ok, %{"cut" => false}} = claim(id, token, r, cc)

    assert {:ok, %{"state" => "sdk-confirmed", "cutResult" => "not-requested"}} =
             finish(id, token, r, cc, %{"success" => true})
  end

  test "a relay restart marks in-flight output uncertain and stops queued output", c do
    {id, token, r, [a, b]} = connected_session(c, ~w(R02-A R02-B))
    assert {:ok, _} = Labels.request(c.user, :print, id, %{}, "mcp")
    assert {:ok, _} = claim(id, token, r, a)

    # The same tab reloads (same client ID) and has nothing in flight.
    assert {:ok, _} = Labels.relay(:relay, id, token, Map.put(r, "restarted", true))
    assert states(id) == ~w(uncertain preview-only)
    assert {:error, 409, _} = finish(id, token, r, a, %{"success" => true, "cutSuccess" => true})
    assert {:error, 409, _} = claim(id, token, r, b)
  end

  test "optional owner approval shows the whole batch and queues it with one click", c do
    {id, token, r, [a, b]} = connected_session(c, ~w(R02-A R02-B))
    batch = mcp(c.mcp, "print", %{"session_id" => id, "approval" => true})
    assert %{"state" => "awaiting-approval", "count" => 2, "approvalUrl" => url} = batch
    assert {:error, 409, _} = claim(id, token, r, a)
    assert {:error, 400, _} = Labels.request(c.user, :approve, id, %{"batchId" => batch["batchId"]}, "mcp")

    path = URI.parse(url).path
    {other_browser, _} = log_in_user(build_conn(), %{scopes: ["assets:write"]})
    {:ok, other_view, _} = live(other_browser, path)
    refute has_element?(other_view, "#approve-label")

    {:ok, view, _} = live(c.browser, path)
    assert has_element?(view, "#batch-labels img[data-part='label-preview']")
    assert view |> element("#approval-operation") |> render() =~ "Print 2 labels, cut after each label"
    view |> element("#approve-label") |> render_click()
    assert states(id) == ~w(queued queued)
    assert has_element?(view, "#approve-label[disabled]")
    assert {:ok, _} = claim(id, token, r, a)
    assert {:ok, _} = finish(id, token, r, a, %{"success" => true, "cutSuccess" => true})
    assert {:ok, _} = claim(id, token, r, b)

    {:ok, connection, _} = live(c.browser, "/operations/labels/#{id}")
    assert has_element?(connection, "#session-labels")
  end

  test "zoneless continuous nylon review shows bitmap sizing and freezes the supply", c do
    {id, token, r, [a]} = connected_session(c, ["larch-runner-a01"])

    nylon =
      Map.merge(r, %{
        "supply" => "M21-750-499",
        "dimensions" => "0 x 0.75",
        "supplyWidth" => "0.75",
        "supplyHeight" => "0",
        "mediaIsDieCut" => false,
        "zoneDimensions" => []
      })

    assert {:ok, _} = Labels.relay(:relay, id, token, nylon)
    preview = mcp(c.mcp, "preview", %{"session_id" => id, "job_id" => a})
    assert %{"mode" => "continuous", "bitmapWidthPx" => 400, "bitmapHeightPx" => 96} = preview["sizing"]
    assert_in_delta preview["sizing"]["nominalLengthMm"], 66.675, 0.001

    batch = mcp(c.mcp, "print", %{"session_id" => id, "approval" => true})
    assert batch["state"] == "awaiting-approval"
    assert {:error, 409, _} = claim(id, token, nylon, a)
    assert {:error, 400, _} = Labels.request(c.user, :approve, id, %{"batchId" => batch["batchId"]}, "mcp")
    {:ok, view, _} = live(c.browser, URI.parse(batch["approvalUrl"]).path)
    assert has_element?(view, "#batch-labels [data-part='label-sizing']", "Physical size is not guaranteed")
    assert has_element?(view, "#batch-labels [data-part='label-sizing']", "66.7 mm")

    for change <- [
          %{"supplyWidth" => "0.5"},
          %{"supplyHeight" => "0.5"},
          %{"mediaIsDieCut" => true},
          %{"zoneDimensions" => r["zoneDimensions"]},
          %{"supply" => r["supply"]}
        ] do
      assert {:ok, _} = Labels.relay(:relay, id, token, Map.merge(nylon, change))
      assert {:error, 409, _} = Labels.request(c.user, :approve, id, %{"batchId" => batch["batchId"]}, "dashboard")
    end

    assert {:ok, _} = Labels.relay(:relay, id, token, nylon)
    view |> element("#approve-label") |> render_click()
    assert {:ok, _} = Labels.relay(:relay, id, token, %{nylon | "supplyWidth" => "0.5"})
    assert {:error, 409, _} = claim(id, token, nylon, a)
    assert {:ok, _} = Labels.relay(:relay, id, token, nylon)
    assert {:ok, %{"zoneDimensions" => [], "sizing" => sizing}} = claim(id, token, nylon, a)
    assert sizing == preview["sizing"]
    assert {:ok, %{"state" => "uncertain"}} = finish(id, token, nylon, a, %{"success" => false})
    assert {:error, 409, _} = Labels.request(c.user, :print, id, %{})
  end

  test "missing or invalid zones only pass for explicitly continuous zero-height media", c do
    {id, token, r, _} = connected_session(c, ~w(TEST))

    continuous =
      Map.merge(r, %{"zoneDimensions" => [], "supplyWidth" => 0.75, "supplyHeight" => 0, "mediaIsDieCut" => false})

    for change <- [
          %{"mediaIsDieCut" => nil},
          %{"mediaIsDieCut" => true},
          %{"supplyHeight" => nil},
          %{"supplyHeight" => "invalid"},
          %{"supplyHeight" => "0.1"},
          %{"supplyWidth" => "0"},
          %{"supplyWidth" => "0.76"},
          %{"supplyWidth" => "0.75in"},
          %{"zoneDimensions" => nil},
          %{"zoneDimensions" => [%{"Width" => 0, "Height" => 0}]}
        ] do
      assert {:ok, _} = Labels.relay(:relay, id, token, Map.merge(continuous, change))
      assert {:error, 409, _} = Labels.request(c.user, :print, id, %{})
    end

    assert {:ok, _} = Labels.relay(:relay, id, token, continuous)
    assert {:ok, %{"state" => "queued"}} = Labels.request(c.user, :print, id, %{})
  end

  test "continuous feed limit uses uploaded bitmap aspect ratio, not requested preview mm", c do
    {id, token, r, _} = connected_session(c, ~w(TEST))

    continuous =
      Map.merge(r, %{"zoneDimensions" => [], "supplyWidth" => "0.75", "supplyHeight" => "0", "mediaIsDieCut" => false})

    assert {:ok, _} = Labels.relay(:relay, id, token, continuous)

    # 200 x 5 produces a 40:1 bitmap, about 640 mm on this tape, not 200 mm.
    mcp(c.mcp, "submit", %{"session_id" => id, "items" => [%{"text" => "LONG"}], "width_mm" => 200, "height_mm" => 5})
    {:ok, %{"jobs" => [_, long]}} = Labels.request(c.user, :status, id)
    preview = mcp(c.mcp, "preview", %{"session_id" => id, "job_id" => long["id"]})

    mcp(c.mcp, "submit", %{
      "session_id" => id,
      "items" => [%{"png" => preview["png"]}],
      "width_mm" => 50,
      "height_mm" => 10
    })

    {:ok, %{"jobs" => [_, _, uploaded]}} = Labels.request(c.user, :status, id)
    assert {:error, 400, _} = Labels.request(c.user, :print, id, %{"jobIds" => [uploaded["id"]]})
    assert states(id) == ~w(preview-only preview-only preview-only)
  end

  test "printer or supply changes, lease loss and expiry block output", c do
    {id, token, r, [a]} = connected_session(c, ~w(RACK-09))
    other_zone = %{r | "zoneDimensions" => [%{"Width" => "45", "Height" => "10"}]}
    assert {:ok, _} = Labels.relay(:relay, id, token, %{r | "zoneDimensions" => [%{"Width" => "0", "Height" => "10"}]})
    assert {:error, 409, _} = Labels.request(c.user, :print, id, %{})
    assert {:ok, _} = Labels.relay(:relay, id, token, %{r | "cutReady" => false})
    assert {:error, 409, _} = Labels.request(c.user, :print, id, %{})
    assert {:ok, _} = Labels.request(c.user, :print, id, %{"cut" => false})
    assert {:ok, _} = Labels.relay(:relay, id, token, %{r | "cutReady" => false} |> Map.merge(other_zone))
    assert {:error, 409, _} = claim(id, token, r, a)
    assert {:error, 409, _} = Labels.relay(:relay, id, token, %{r | "clientId" => "another-active-relay"})

    # A queued batch that the relay never started returns to preview when its deadline passes.
    j = Repo.get!(Job, a)
    Repo.update!(Ecto.Changeset.change(j, data: Map.put(j.data, "claimBy", 0)))
    assert {:ok, %{"jobs" => [%{"state" => "preview-only", "note" => note}]}} = Labels.request(c.user, :status, id)
    assert note =~ "expired"

    # So does an approval nobody gave in time; a standalone cut is dropped instead.
    assert {:ok, _} = Labels.relay(:relay, id, token, r)
    assert {:ok, %{"batchId" => batch}} = Labels.request(c.user, :print, id, %{"approval" => true})
    assert {:ok, %{"jobs" => [cut]}} = Labels.request(c.user, :cut, id, %{"approval" => true})

    for job <- Repo.all(from(j in Job, where: j.session_id == ^id)),
        do: Repo.update!(Ecto.Changeset.change(job, data: Map.put(job.data, "approvalExpiresAt", 0)))

    assert {:error, 409, _} = Labels.request(c.user, :approve, id, %{"batchId" => batch}, "dashboard")
    assert {:ok, %{"counts" => %{"preview-only" => 1}}} = Labels.request(c.user, :status, id)
    assert states(id) == ~w(preview-only)
    refute Repo.get(Job, cut["id"])

    Repo.update!(Ecto.Changeset.change(Repo.get!(Session, id), expires_at: DateTime.add(DateTime.utc_now(), -1)))
    assert {:error, 404, _} = Labels.request(c.user, :status, id)
    assert {:error, 404, _} = Labels.relay(:status, id, token)
  end

  test "a standalone cut runs directly and needs a cut-capable relay", c do
    {id, token, r, _} = connected_session(c, ~w(CUT-09))
    assert {:ok, _} = Labels.relay(:relay, id, token, %{r | "cutReady" => false})
    assert %{"isError" => true} = ManageLabelSession.call(c.mcp, %{"action" => "cut", "session_id" => id})
    assert {:ok, _} = Labels.relay(:relay, id, token, r)
    assert %{"state" => "queued", "jobs" => [%{"id" => cut}]} = mcp(c.mcp, "cut", %{"session_id" => id})
    assert {:ok, %{"action" => "cut", "state" => "dispatched"}} = claim(id, token, r, cut)

    assert {:ok, %{"state" => "sdk-confirmed", "cutResult" => "sdk-confirmed"}} =
             finish(id, token, r, cut, %{"success" => true})

    assert {:error, 409, _} = claim(id, token, r, cut)
  end

  test "the owner's connection page issues a relay credential when the link lost it", c do
    {id, token, r, _} = connected_session(c, ~w(R02-A R02-B R02-C))
    {:ok, view, _} = live(c.browser, "/operations/labels/#{id}")

    # Rows are numbered by position in the session, not by a batch they are not in yet.
    positions =
      view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query("#session-labels [data-part='label-position']")

    assert Enum.map(positions, &LazyHTML.text/1) == ~w(1 2 3)

    # The relay tab that reported moments ago keeps the printer.
    render_hook(view, "relay_token", %{"clientId" => "a-different-relay-tab"})
    assert_reply(view, %{error: "Another Chrome relay tab is active." <> _})
    assert {:ok, _} = Labels.relay(:status, id, token)

    # The same tab, or any tab once the relay went quiet, gets a fresh credential.
    render_hook(view, "relay_token", %{"clientId" => r["clientId"]})
    assert_reply(view, %{token: fresh})
    assert {:error, 401, _} = Labels.relay(:status, id, token)
    assert {:ok, %{"id" => ^id}} = Labels.relay(:status, id, fresh)

    {other_browser, _} = log_in_user(build_conn(), %{scopes: ["assets:write"]})
    {:ok, other_view, _} = live(other_browser, "/operations/labels/#{id}")
    render_hook(other_view, "relay_token", %{"clientId" => r["clientId"]})
    assert_reply(other_view, %{error: _})
    assert {:ok, _} = Labels.relay(:status, id, fresh)
  end

  test "MCP is personal, schema checked and cannot approve", c do
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
