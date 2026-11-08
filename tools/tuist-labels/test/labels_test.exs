defmodule TuistLabelsTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn
  alias TuistLabels.Store

  defp call(method, path, token \\ nil, body \\ %{}) do
    conn(method, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> then(fn c ->
      if token, do: put_req_header(c, "authorization", "Bearer " <> token), else: c
    end)
    |> TuistLabelsWeb.Endpoint.call([])
  end

  defp json(conn), do: Jason.decode!(conn.resp_body)

  test "the browser only connects the printer; sessions and preparation belong to the CLI" do
    for path <- ["/", "/relay"] do
      page = call(:get, path)
      assert page.status == 200
      html = Floki.parse_document!(page.resp_body)
      assert Floki.find(html, "[data-phx-main] .noora-card") != []
      assert Floki.find(html, "script[src='/assets/app.js']") != []
      assert Floki.find(html, "form, textarea, input, button") == []
      assert Floki.text(html) =~ "tuist-labels init"
      assert get_resp_header(page, "referrer-policy") == ["no-referrer"]
    end
  end

  test "HTTP sessions isolate roles; text and PNG previews are real, atomic and never print" do
    s = call(:post, "/api/sessions") |> json()
    path = "/api/sessions/" <> s["id"]
    assert call(:get, path).status == 401
    other = call(:post, "/api/sessions") |> json()
    assert call(:get, path, other["controlToken"]).status == 401

    assert call(:post, path <> "/jobs", s["relayToken"], %{"items" => [%{"text" => "NO"}]}).status ==
             403

    assert call(:post, path <> "/jobs", s["controlToken"], %{
             "items" => [%{"text" => "BER1-P09"}, %{"text" => ""}]
           }).status == 400

    assert json(call(:get, path, s["controlToken"]))["jobs"] == []

    assert call(:post, path <> "/jobs", s["controlToken"], %{
             "items" => [%{"text" => "BER1-P09"}, %{"text" => "SW02 & <UPLINK>"}],
             "widthMm" => 38.1,
             "heightMm" => 10
           }).status == 201

    state = json(call(:get, path, s["relayToken"]))
    assert Enum.map(state["jobs"], & &1["title"]) == ["BER1-P09", "SW02 & <UPLINK>"]
    refute state["printingEnabled"]
    [job | _] = state["jobs"]
    image = call(:get, path <> "/jobs/#{job["id"]}.png", s["controlToken"])

    assert <<137, 80, 78, 71, 13, 10, 26, 10, 13::32, "IHDR", 305::32, 80::32, _::binary>> =
             image.resp_body

    assert call(:post, path <> "/jobs", s["controlToken"], %{
             "items" => [%{"png" => Base.encode64(image.resp_body)}]
           }).status == 201

    assert call(:post, path <> "/jobs", s["controlToken"], %{"items" => [%{"png" => "invalid"}]}).status ==
             400

    assert call(:post, path <> "/print", s["controlToken"], %{"jobId" => job["id"]}).status == 403
    assert call(:post, path <> "/cut", s["controlToken"]).status == 403
    assert call(:post, path <> "/relay", s["controlToken"], %{}).status == 403

    report = %{
      "clientId" => "chrome-test-client",
      "connected" => true,
      "name" => "M211",
      "supplyWidth" => 19.05
    }

    assert call(:post, path <> "/relay", s["relayToken"], report).status == 200

    assert call(
             :post,
             path <> "/relay",
             s["relayToken"],
             Map.put(report, "clientId", "competing-client")
           ).status == 409

    assert json(call(:get, path, s["controlToken"]))["relay"]["supplyWidth"] == "19.05"

    assert call(:post, path <> "/jobs/#{job["id"]}/claim", s["relayToken"], %{
             "clientId" => report["clientId"]
           }).status == 409
  end

  defp authorized(context) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "labels-test-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
      )

    File.mkdir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    s = %{
      "id" => "test-session",
      "controlToken" => "test-control",
      "relayToken" => "test-relay",
      "expiresAt" => Store.now() + 60_000
    }

    auth = %{
      "sessionId" => s["id"],
      "text" => "ASYMMETRIC-09",
      "printer" => "M211-ONE",
      "supply" => "SUPPLY-427",
      "allowCut" => context[:cut] == true
    }

    opts = [name: nil, session: s, authorization: auth, journal: Path.join(dir, "dispatch.json")]
    server = start_supervised!({Store, opts})

    %{
      server: server,
      opts: opts,
      s: s,
      report: %{
        "clientId" => "chrome-test-client",
        "connected" => true,
        "name" => auth["printer"],
        "supply" => auth["supply"],
        "cutReady" => true
      }
    }
  end

  defp req(c, action, data \\ %{}, role \\ "controlToken"),
    do: Store.request({action, c.s["id"], c.s[role], data}, c.server)

  @tag cut: true
  test "one print and separate cut consume durable approvals once, including concurrent claims and restart",
       context do
    c = authorized(context)
    assert {:error, 409, _} = req(c, :cut)
    assert {:ok, _} = req(c, :relay, c.report, "relayToken")

    assert {:ok, _} =
             req(c, :submit, %{"items" => [%{"text" => "WRONG"}, %{"text" => "ASYMMETRIC-09"}]})

    {:ok, %{"jobs" => [wrong, job]}} = req(c, :status)
    assert {:error, 403, _} = req(c, :print, %{"jobId" => wrong["id"]})
    assert {:ok, _} = req(c, :relay, Map.put(c.report, "supply", "WRONG"), "relayToken")
    assert {:error, 409, _} = req(c, :print, %{"jobId" => job["id"]})
    assert {:ok, _} = req(c, :relay, c.report, "relayToken")
    assert {:ok, %{"state" => "queued"}} = req(c, :print, %{"jobId" => job["id"]})
    data = %{"jobId" => job["id"], "clientId" => c.report["clientId"]}

    replies =
      1..2
      |> Task.async_stream(fn _ -> req(c, :claim, data, "relayToken") end)
      |> Enum.map(fn {:ok, result} -> elem(result, 0) end)

    assert Enum.sort(replies) == [:error, :ok]
    assert Bitwise.band(File.stat!(c.opts[:journal]).mode, 0o777) == 0o600
    assert Jason.decode!(File.read!(c.opts[:journal]))["title"] == "ASYMMETRIC-09"

    assert {:ok, %{"state" => "uncertain"}} =
             req(c, :result, Map.put(data, "success", false), "relayToken")

    assert {:error, 409, _} = req(c, :claim, data, "relayToken")
    assert {:ok, %{"jobId" => cut}} = req(c, :cut)
    cut_data = %{data | "jobId" => cut}
    assert {:ok, _} = req(c, :claim, cut_data, "relayToken")
    assert File.exists?(c.opts[:journal] <> ".cut")
    assert {:error, 409, _} = req(c, :claim, cut_data, "relayToken")
    stop_supervised(Store)
    restarted = %{c | server: start_supervised!({Store, c.opts})}
    assert {:ok, _} = req(restarted, :relay, c.report, "relayToken")
    assert {:ok, _} = req(restarted, :submit, %{"items" => [%{"text" => "ASYMMETRIC-09"}]})
    {:ok, %{"jobs" => [new]}} = req(restarted, :status)
    assert {:ok, _} = req(restarted, :print, %{"jobId" => new["id"]})
    assert {:error, 409, _} = req(restarted, :claim, %{data | "jobId" => new["id"]}, "relayToken")
    assert {:ok, %{"jobId" => new_cut}} = req(restarted, :cut)
    assert {:error, 409, _} = req(restarted, :claim, %{data | "jobId" => new_cut}, "relayToken")
  end

  test "missing cut approval and unwritable dispatch journal fail closed" do
    c = authorized(%{})
    assert {:error, 403, _} = req(c, :cut)
    File.mkdir!(c.opts[:journal])
    assert {:ok, _} = req(c, :relay, c.report, "relayToken")
    assert {:ok, _} = req(c, :submit, %{"items" => [%{"text" => "ASYMMETRIC-09"}]})
    {:ok, %{"jobs" => [job]}} = req(c, :status)
    assert {:ok, _} = req(c, :print, %{"jobId" => job["id"]})

    assert {:error, _, _} =
             req(
               c,
               :claim,
               %{"jobId" => job["id"], "clientId" => c.report["clientId"]},
               "relayToken"
             )

    assert {:ok, %{"jobs" => [%{"state" => "queued"}]}} = req(c, :status)
  end

  test "expired sessions cannot read or submit jobs" do
    s = %{"id" => "expired", "controlToken" => "control", "expiresAt" => Store.now() - 1}
    server = start_supervised!({Store, name: nil, session: s})
    assert {:error, 401, _} = Store.request({:status, s["id"], s["controlToken"], false}, server)
  end

  test "startup stays preview-only unless explicitly configured; restoration retains consumed markers" do
    c = authorized(%{})
    dir = Path.dirname(c.opts[:journal])
    env = System.get_env() |> Map.take(~w(M211_STATE_DIR M211_SESSION M211_AUTHORIZATION))

    on_exit(fn ->
      Enum.each(~w(M211_STATE_DIR M211_SESSION M211_AUTHORIZATION), &System.delete_env/1)
      System.put_env(env)
    end)

    System.put_env(%{"M211_STATE_DIR" => dir, "M211_SESSION" => "", "M211_AUTHORIZATION" => ""})
    assert Store.config() == []
    File.write!(Path.join(dir, "session.json"), Jason.encode!(c.s))
    auth_path = Path.join(dir, "authorization.json")
    auth = Map.put(c.opts[:authorization], "id", "approved-09")
    File.write!(auth_path, Jason.encode!(auth))
    System.put_env("M211_AUTHORIZATION", auth_path)
    marker = Path.join(dir, "dispatch-approved-09.json")
    File.write!(marker, "consumed")
    restored = Store.config()
    assert restored[:session] == c.s
    assert restored[:journal] == marker
    assert File.read!(marker) == "consumed"
    File.write!(auth_path, Jason.encode!(Map.put(auth, "id", "../unsafe")))
    assert_raise RuntimeError, "Invalid single-use authorization.", &Store.config/0
    File.write!(auth_path, Jason.encode!(Map.put(auth, "sessionId", "another-session")))

    assert_raise RuntimeError,
                 "Authorization must match the saved, unexpired CLI session.",
                 &Store.config/0
  end
end
