defmodule Symptoms.PipelineTest do
  use Symptoms.DataCase
  use Mimic

  alias Symptoms.Evidence.Combine
  alias Symptoms.FakeSource
  alias Symptoms.Log
  alias Symptoms.Pipeline
  alias Symptoms.Store
  alias Symptoms.Store.AuditEvent
  alias Symptoms.Store.Revision
  alias Symptoms.Store.Symptom

  # Monday 11:00 Berlin (day hours: review in 60 minutes, day price 600).
  @t0 ~U[2026-11-16 10:00:00.000000Z]

  @route %{service: "tuist-server", kind: "route", key: "POST /api/runs"}

  # Hand calculation. The seeded null history has n = 180 windows at this
  # hour of week, all below 1.0.
  #
  # - Loud window (statistic 100): p = (1 + 0) / 181, e = 0.5 · p^-0.5 =
  #   0.5 · √181 = 6.7268, x = ln e = 1.9061 nats (above degraded_nats 1).
  #   CUSUM with drift 0 and h = 6: 1.906, 3.812, 5.718, 7.624, so the 4th
  #   loud window (index 3) crosses.
  #   Loud windows before the crossing are the entity's degraded run, so they
  #   stay out of the history and every loud window gets the same e.
  # - Quiet window (statistic 0.5): the values rem(37 i, 100) / 100 for
  #   i = 0..99 take each of 0.00–0.99 once (37 is coprime with 100): 50 are
  #   ≥ 0.5. For i = 100..179 they repeat j = 0..79: 37 j mod 100 = 0, 37,
  #   74, 11, 48, 85, 22, 59, 96, 33, … ; enumerating the 80 gives 39 at or
  #   above 50. So 89 of 180, p = 90 / 181, e = 0.5 / √(90/181) = 0.7091,
  #   x = −0.3438 < 0.
  @loud_x :math.log(0.5 * :math.sqrt(181))
  @quiet_x :math.log(0.5 / :math.sqrt(90 / 181))

  setup do
    FakeSource.seed_history([@route], @t0)
    :ok
  end

  defp window(i), do: DateTime.shift(@t0, minute: i)

  defp run(i, statistic, entities \\ [@route], rate \\ 50.0) do
    Process.put(:fake_source, fn window -> {:ok, FakeSource.records(window, entities, statistic, rate)} end)
    Pipeline.run_window(60, window(i), sources: [FakeSource])
  end

  defp symptoms, do: Repo.all(from(s in Symptom, order_by: s.opened_at))
  defp revisions, do: Repo.all(from(r in Revision, order_by: r.seq))

  test "the hand-calculated per-window evidence matches the stored windows" do
    run(0, 100)
    run(1, 0.5)

    [loud, quiet] =
      Repo.all(
        from(w in Store.StreamWindow,
          where: w.window_start >= ^@t0,
          order_by: w.window_start,
          select: {w.p, w.e}
        )
      )

    assert loud == {1 / 181, 0.5 * :math.sqrt(181)}
    assert_in_delta :math.log(elem(quiet, 1)), @quiet_x, 1.0e-12
  end

  test "rerunning a window applies its evidence only once" do
    for _ <- 1..4, do: run(0, 100)
    assert [%{window_start: @t0}] = Repo.all(Store.RootScore)
    assert_in_delta Repo.one!(Store.DetectorState).cusum, @loud_x, 1.0e-12
    assert symptoms() == []
  end

  test "a failure writing completion rolls back detection and recovery applies the window once" do
    stub(Repo, :insert_all, fn schema, rows, opts ->
      if schema == Store.PipelineRun and Process.get(:fail_completion) do
        raise "completion failed"
      end

      call_original(Repo, :insert_all, [schema, rows, opts])
    end)

    Process.put(:fail_completion, true)
    assert_raise RuntimeError, "completion failed", fn -> run(0, 100) end
    assert Repo.all(Store.DetectorState) == []
    assert Repo.all(Store.RootScore) == []
    assert Repo.all(Store.PipelineRun) == []

    Process.put(:fail_completion, false)
    run(0, 100)
    assert_in_delta Repo.one!(Store.DetectorState).cusum, @loud_x, 1.0e-12
  end

  test "source failures hold an incident unknown until affirmative recovery" do
    for i <- 0..3, do: run(i, 100)
    [%{id: id}] = symptoms()

    Process.put(:fake_source, fn _ -> {:error, :timeout} end)
    for i <- 4..9, do: Pipeline.run_window(60, window(i), sources: [FakeSource])
    assert Repo.get!(Symptom, id).state == "open"
    assert Repo.get!(Store.Entity, Store.entity_id(@route)).unknown

    for i <- 10..14, do: run(i, 0.5)
    assert Repo.get!(Symptom, id).state == "resolved"
    refute Repo.get!(Store.Entity, Store.entity_id(@route)).unknown
  end

  test "a failed stream is not cleared by healthy evidence from another stream" do
    for i <- 0..3, do: run(i, 100)
    [%{id: id}] = symptoms()

    # The source still has a healthy error-share record, but cannot read latency.
    Process.put(:fake_source, fn w, opts ->
      opts[:unknown].("latency", [@route])
      {:ok, FakeSource.records(w, [@route], 0.5)}
    end)

    for i <- 4..9, do: Pipeline.run_window(60, window(i), sources: [FakeSource])

    assert Repo.get!(Symptom, id).state == "open"
  end

  test "a missing stream stays unknown across windows until that stream recovers" do
    for i <- 0..3, do: run(i, 100)
    [%{id: id}] = symptoms()

    Process.put(:fake_source, fn w, opts ->
      opts[:unknown].("fake.latency", [@route])
      {:ok, FakeSource.records(w, [@route], 0.5)}
    end)

    Pipeline.run_window(60, window(4), sources: [FakeSource])

    # The minute source keeps returning errors data, but no latency data.
    for i <- 5..10, do: run(i, 0.5)
    assert Repo.get!(Symptom, id).state == "open"
    assert Repo.get!(Store.Entity, Store.entity_id(@route)).unknown

    Process.put(:fake_source, fn w ->
      records = FakeSource.records(w, [@route], 0.5)
      latency = for r <- records, do: %{r | source: "fake.latency", window_seconds: 300}
      {:ok, records ++ latency}
    end)

    Pipeline.run_window(60, window(11), sources: [FakeSource])
    for i <- 12..15, do: run(i, 0.5)
    assert Repo.get!(Symptom, id).state == "resolved"
    refute Repo.get!(Store.Entity, Store.entity_id(@route)).unknown
  end

  test "a merged caller separates when its dependency recovers but the caller stays degraded" do
    callee = %{@route | key: "postgres query"}
    FakeSource.seed_history([callee], @t0)
    for i <- 0..3, do: run(i, 100, [@route, callee], 1.0)
    caller_id = Store.entity_id(@route)
    original = Repo.one!(from(s in Symptom, where: s.entity_id == ^caller_id))

    Store.put_edges("test", [{@route, callee}])
    run(4, 100, [@route, callee], 1.0)
    assert Repo.get!(Symptom, original.id).state == "merged"

    for i <- 5..10 do
      Process.put(:fake_source, fn w ->
        {:ok, FakeSource.records(w, [@route], 100, 1.0) ++ FakeSource.records(w, [callee], 0.5, 0.0)}
      end)

      Pipeline.run_window(60, window(i), sources: [FakeSource])
      caller = Repo.get!(Symptom, original.id)
      assert caller.state == "open"
      assert caller.root_key == "60:entity:#{caller_id}"
      assert caller.merged_into == nil
      assert caller.document["root"]["root_symptom_id"] == caller.id
    end

    assert Repo.aggregate(from(s in Symptom, where: s.entity_id == ^caller_id), :count) == 1
  end

  test "a board push and an outcome committed after the window read the symptoms survive its revision" do
    # Impact 1 per minute: P = σ(7.62 − 6) = 0.8355, cost 0.8355 · 1 · 60 =
    # 50 < 600, so the symptom opens at board tier in window 3.
    for i <- 0..3, do: run(i, 100, [@route], 1.0)
    [%{id: id, tier: "board"}] = symptoms()
    board_at = window(5)

    # Window 4 reads the open symptoms, then steps the CUSUMs. Before its
    # transaction, the board push (always delayed: `random` 0.0 gives
    # delayed_until = now + 10 min) and the state read-back (a bad outcome)
    # commit.
    stub(Combine, :cusum_step, fn s, x, drift ->
      if Process.put(:injected, true) == nil do
        previous = Application.get_env(:symptoms, :policy)
        Application.put_env(:symptoms, :policy, random: {__MODULE__, :always, []})
        assert [^id] = Symptoms.Board.push(board_at)
        Application.put_env(:symptoms, :policy, previous)

        outcome = %{
          "symptom_id" => id,
          "outcome" => "bad",
          "confirmed_at" => DateTime.to_iso8601(board_at),
          "change_seq" => 1
        }

        Symptoms.State.apply_page(%{"outcomes" => [outcome], "next" => 1}, 0, board_at)
      end

      call_original(Combine, :cusum_step, [s, x, drift])
    end)

    # Impact 1 → 2.5 (×2.5) is a material change: window 4 writes an
    # annotated revision (still board: 0.971 · 2.5 · 60 = 146 < 600).
    run(4, 100, [@route], 2.5)

    symptom = Repo.get!(Symptom, id)
    latest = List.last(revisions()).document
    assert latest["transition"] == "annotated"
    assert latest["impact"]["rate"] == 2.5
    assert %{"rank" => 1, "delayed_until" => delayed} = latest["board"]
    assert delayed == DateTime.to_iso8601(DateTime.shift(board_at, minute: 10))
    assert %{"outcome" => "bad"} = latest["outcome"]
    assert symptom.delayed_until == DateTime.shift(board_at, minute: 10)
  end

  def always, do: 0.0

  test "a delayed page is not sent once the entity was muted during the delay" do
    Application.put_env(:symptoms, :policy, random: {__MODULE__, :always, []})
    # Window 3 (now t0 + 4 min) pages, delayed by 10 minutes (random 0.0):
    # until t0 + 14 min.
    for i <- 0..3, do: run(i, 100)
    [%{id: id, charged: true, delayed_until: until}] = symptoms()
    assert until == DateTime.shift(@t0, minute: 14)

    # A person mutes the entity and phenomenon during the delay.
    Repo.insert!(%Store.HumanMute{
      environment: "production",
      service: "tuist-server",
      kind: "route",
      key: "POST /api/runs",
      phenomenon: "request_errors",
      expires_at: DateTime.shift(@t0, hour: 2),
      change_seq: 1
    })

    # Windows 4–13 end at t0 + 5 … t0 + 14 min; the delay has passed by the last.
    for i <- 4..13, do: run(i, 100)

    assert Repo.get!(Symptom, id).paged_at == nil
    assert Repo.all(from(a in AuditEvent, where: a.kind in ["page_sent", "page_logged"])) == []
  end

  test "a mute on the trimmed form of a long entity key matches the entity" do
    long = %{@route | key: "GET /api/" <> String.duplicate("segment/", 40)}
    FakeSource.seed_history([long], @t0)

    # README "Symptom log": the first 200 characters plus `…sha256:` and the
    # hex SHA-256 of the whole key, as a snapshot over 16 KB carries it.
    digest = :sha256 |> :crypto.hash(long.key) |> Base.encode16(case: :lower)
    trimmed = String.slice(long.key, 0, 200) <> "…sha256:" <> digest

    Repo.insert!(%Store.HumanMute{
      environment: "production",
      service: "tuist-server",
      kind: "route",
      key: trimmed,
      phenomenon: "request_errors",
      expires_at: DateTime.shift(@t0, hour: 2),
      change_seq: 1
    })

    # Unmuted this would page (as in the loud-failure test); muted it goes to
    # audit and never pages.
    for i <- 0..3, do: run(i, 100, [long])
    assert [%{tier: "audit", charged: false, paged_at: nil}] = symptoms()
  end

  test "an unchanged board root writes no revision from its delay draws" do
    # Every draw delays (random 0.0): delayed_until = now + 10 min, a new
    # value each window.
    Application.put_env(:symptoms, :policy, random: {__MODULE__, :always, []})
    for i <- 0..3, do: run(i, 100, [@route], 1.0)
    [%{tier: "board", charged: false}] = symptoms()

    # From window 4 on the entity is unknown: x = 0 neither counts as quiet
    # nor resets, so score, P, impact and tier stay as they are. Over 37
    # windows (more than two 15-minute coalescing periods) only a new delay
    # draw could change the snapshot.
    Process.put(:fake_source, fn _window -> {:unknown, [@route]} end)
    for i <- 4..40, do: Pipeline.run_window(60, window(i), sources: [FakeSource])

    assert Enum.map(revisions(), & &1.document["transition"]) == ["opened"]
  end

  test "the snapshot publishes the symptom's own phenomenon, the one mutes match" do
    # `phenomena` lists every phenomenon with evidence; `phenomenon` is the
    # one the symptom was opened for and the one a mute must name.
    for i <- 0..3, do: run(i, 100)
    [%{id: id, phenomenon: phenomenon}] = symptoms()
    assert phenomenon == "request_errors"
    assert Log.latest(id)["phenomenon"] == "request_errors"
    assert Enum.all?(revisions(), &(&1.document["phenomenon"] == "request_errors"))
  end

  test "a quiet stream opens nothing" do
    for i <- 0..29, do: run(i, 0.5)

    assert symptoms() == []
    assert revisions() == []
    assert Repo.all(Store.DetectorState) == []
  end

  test "a loud failure opens a symptom within minutes, then resolves after quiet windows" do
    for i <- 0..2, do: assert(run(i, 100).opened == [])

    # 3 · 1.906 = 5.718 < 6 above; 4 · 1.906 = 7.624 ≥ 6 now.
    assert %{opened: [id]} = run(3, 100)
    [symptom] = symptoms()
    assert symptom.id == id
    assert symptom.state == "open"
    assert_in_delta symptom.score, 4 * @loud_x, 1.0e-9
    assert symptom.document["transition"] == "opened"
    assert symptom.document["entity"]["key"] == "POST /api/runs"

    # P = sigmoid(7.624 − 6) = 0.8355; cost = 0.8355 · 50 · 60 = 2507 > 600.
    assert symptom.tier == "page"
    assert symptom.document["decision"]["would_page"]

    # Quiet windows: x = −0.344 each. The 5th consecutive quiet window resolves.
    for i <- 4..7, do: assert(run(i, 0.5).resolved == [])
    assert %{resolved: [^id]} = run(8, 0.5)

    resolved = Repo.get!(Symptom, id)
    assert resolved.state == "resolved"
    assert resolved.document["transition"] == "resolved"
    assert Enum.map(revisions(), & &1.document["transition"]) == ["opened", "resolved"]

    # The degraded run is marked with its symptom.
    assert Repo.aggregate(from(w in Store.StreamWindow, where: w.window_start >= ^@t0 and w.open_symptom), :count) ==
             9
  end

  test "a page is sent only after the window's transaction commits" do
    test = self()
    previous = Application.get_env(:symptoms, :paging)
    on_exit(fn -> Application.put_env(:symptoms, :paging, previous) end)

    plug = fn conn ->
      send(test, {:paged, Repo.in_transaction?()})
      Plug.Conn.send_resp(conn, 200, "")
    end

    Application.put_env(:symptoms, :paging,
      enabled: true,
      webhook_url: "http://irm.invalid/hook",
      req_options: [plug: plug]
    )

    for i <- 0..3, do: run(i, 100)
    assert_received {:paged, false}
    refute_received {:paged, _}
    assert [%{paged_at: %DateTime{}}] = symptoms()
  end

  test "a page logged with paging off records no paged_at and is logged once" do
    # Paging is off in test: window 3 would page (cost 2507 > 600).
    for i <- 0..6, do: run(i, 100)

    assert [%{paged_at: nil, page_logged_at: logged}] = symptoms()
    assert logged == window(4)
    assert [_] = Repo.all(from(a in AuditEvent, where: a.kind == "page_logged"))
  end

  test "the same symptom_key reopens the same symptom within 24 hours" do
    for i <- 0..3, do: run(i, 100)
    for i <- 4..8, do: run(i, 0.5)
    [%{id: id, state: "resolved"}] = symptoms()

    # The CUSUM restarted at 0 on resolution. The resolved symptom paged but
    # has no bad label, so its run is null history again: at window 9 the
    # history holds the 180 seeded windows plus today's windows 0–8 (four at
    # 100), n = 189, p = (1 + 4) / 190, e = 0.5 · √38 = 3.0822, x = 1.1256.
    # Windows 9.. are the new run's own, so x stays; 5 · 1.1256 = 5.628 < 6
    # and 6 · 1.1256 = 6.754 ≥ 6: the 6th loud window (14) reopens.
    for i <- 9..13, do: assert(run(i, 100).reopened == [])
    assert %{reopened: [^id], opened: []} = run(14, 100)

    assert [%{id: ^id, state: "open"}] = symptoms()

    assert Enum.map(revisions(), &{&1.document["transition"], &1.revision}) ==
             [{"opened", 1}, {"resolved", 2}, {"reopened", 3}]
  end

  test "a symptom resolved more than 24 hours ago does not reopen" do
    for i <- 0..3, do: run(i, 100)
    for i <- 4..8, do: run(i, 0.5)
    [%{id: id}] = symptoms()

    Repo.update_all(from(s in Symptom, where: s.id == ^id), set: [resolved_at: DateTime.shift(@t0, hour: -25)])

    # As above, the 6th loud window after the first run crosses.
    for i <- 9..14, do: run(i, 100)
    assert [%{id: ^id, state: "resolved"}, %{state: "open", id: other}] = symptoms()
    assert other != id
  end

  test "reopening keeps one-minute and five-minute symptoms separate" do
    for i <- 0..3, do: run(i, 100)
    for i <- 4..8, do: run(i, 0.5)
    [%{id: minute_id, entity_id: entity_id, state: "resolved"}] = symptoms()

    score = %{x: 7.0, phenomena: [], impact_unit: nil, impact_rate: 0.0, examples: []}
    at = DateTime.shift(@t0, minute: 15)
    assert %{opened: [five_minute_id], reopened: []} = Symptoms.Lifecycle.step(300, at, %{entity_id => score}, at)
    assert five_minute_id != minute_id
    assert Repo.get!(Symptom, minute_id).state == "resolved"
    assert Repo.get!(Symptom, minute_id).root_key == "60:entity:#{entity_id}"

    for i <- 1..5 do
      quiet_at = DateTime.shift(at, minute: i * 5)
      Symptoms.Lifecycle.step(300, quiet_at, %{entity_id => %{score | x: -1.0}}, quiet_at)
    end

    assert Repo.get!(Symptom, five_minute_id).state == "resolved"
    reopen_at = DateTime.shift(at, minute: 30)

    assert %{opened: [], reopened: [^five_minute_id]} =
             Symptoms.Lifecycle.step(300, reopen_at, %{entity_id => score}, reopen_at)

    assert Repo.get!(Symptom, five_minute_id).root_key == "300:entity:#{entity_id}"
  end

  test "revisions coalesce to one per 15 minutes without a material change" do
    for i <- 0..20, do: run(i, 100)

    # Opened at window 3 (now = its end, t0 + 4 min). The score grows every
    # window but tier, state, root and impact stay: the next revision is the
    # first window ending 15 minutes later, window 18 (t0 + 19 min).
    assert [opened, annotated] = revisions()
    assert opened.document["transition"] == "opened"
    assert opened.inserted_at == DateTime.shift(@t0, minute: 4)
    assert annotated.document["transition"] == "annotated"
    assert annotated.inserted_at == DateTime.shift(@t0, minute: 19)
    assert annotated.seq > opened.seq
  end

  test "an impact change of 2× is material and is not coalesced" do
    for i <- 0..3, do: run(i, 100)
    run(4, 100, [@route], 50.0)
    run(5, 100, [@route], 100.0)

    assert Enum.map(revisions(), & &1.document["impact"]["rate"]) == [50.0, 100.0]
  end

  describe "a shared-cause outage over a resource" do
    @callers for key <- ~w(a b c), do: %{service: "tuist-server", kind: "route", key: "GET /#{key}"}
    @postgres %{service: "postgres", kind: "resource", key: "postgres"}

    setup do
      FakeSource.seed_history(@callers, @t0)
      {:ok, 3} = Store.put_edges("test", Enum.map(@callers, &%{caller: &1, callee: @postgres, count: 10}))
      :ok
    end

    test "yields one root and one charged page" do
      for i <- 0..2, do: run(i, 100, @callers)
      result = run(3, 100, @callers)

      assert length(result.opened) == 3
      assert [root_key] = result.charged_roots
      assert root_key =~ ":shared:"

      [first | _] = all = symptoms()
      root_ids = all |> Enum.map(& &1.document["root"]["root_symptom_id"]) |> Enum.uniq()
      assert [root_id] = root_ids
      assert Enum.all?(all, & &1.document["root"]["shared_cause"])
      assert Enum.all?(all, &(&1.tier == "page"))
      assert length(Enum.find(all, &(&1.id == root_id)).document["root"]["member_symptom_ids"]) == 2
      assert first.root_key == root_key

      # Charged and delivered (logged, paging is off) once for the root.
      for i <- 4..6, do: run(i, 100, @callers)
      assert Repo.aggregate(from(a in AuditEvent, where: a.kind == "page_charged"), :count) == 1
      assert Repo.aggregate(from(a in AuditEvent, where: a.kind == "page_logged"), :count) == 1
    end
  end

  test "pending windows: the latest finished minute, then catch-up of at most 5" do
    # now 10:05:30 with a 0-second delay: the last whole minute that ended is 10:04.
    now = ~U[2026-11-16 10:05:30.000000Z]
    assert Pipeline.pending_windows(60, now) == [~U[2026-11-16 10:04:00.000000Z]]

    Pipeline.run_window(60, ~U[2026-11-16 09:50:00.000000Z], sources: [])

    assert Pipeline.pending_windows(60, now) ==
             Enum.map(0..4, &DateTime.shift(~U[2026-11-16 10:00:00.000000Z], minute: &1))
  end

  test "an unknown entity is marked, not quiet" do
    Process.put(:fake_source, fn _window -> {:unknown, [@route]} end)
    Pipeline.run_window(60, window(0), sources: [FakeSource])

    assert Repo.one!(from(e in Store.Entity, where: e.key == "POST /api/runs", select: e.unknown))
  end
end
