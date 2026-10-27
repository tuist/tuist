defmodule Atlas.Engineering.Errors.SelfMonitorTest do
  use Atlas.DataCase, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Atlas.Demo
  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Errors.Event
  alias Atlas.Engineering.Errors.IssueCoalescer
  alias Atlas.Engineering.Errors.LoggerHandler
  alias Atlas.Engineering.Errors.SelfMonitor
  alias Atlas.Engineering.Projects.Project
  alias Atlas.Ingestion.Bufferable
  alias Atlas.IngestRepo
  alias Atlas.LLMs.PersonalProviders
  alias Ecto.Adapters.SQL.Sandbox

  require Logger

  setup_all do
    Mimic.copy(Application)
    :ok
  end

  setup do
    configure(clickhouse_enabled: true, sentry_dsn: nil)

    # Keep the installer's node-wide project setting local to the emitting
    # process, so other async tests never capture into this sandbox.
    stub(Application, :put_env, fn :atlas, :errors_self_project_id, id ->
      Process.put(:self_monitor_test_project_id, id)
      :ok
    end)

    :ok
  end

  test "the supervised installer starts after its repositories and ingest pipeline, before the endpoint" do
    specs = Enum.map(Atlas.Application.children(), &Supervisor.child_spec(&1, []))
    ids = Enum.map(specs, & &1.id)

    assert %{start: {Task, :start_link, [_install]}, restart: :temporary} =
             Enum.find(specs, &(&1.id == SelfMonitor))

    for dependency <- [
          Repo,
          Atlas.ClickHouseRepo,
          IngestRepo,
          Event.Buffer,
          Errors.DropAlerter,
          IssueCoalescer,
          Errors.IssueAccountCoalescer,
          Errors.KeyTouches
        ] do
      assert Enum.find_index(ids, &(&1 == dependency)) < Enum.find_index(ids, &(&1 == SelfMonitor))
    end

    assert Enum.find_index(ids, &(&1 == SelfMonitor)) < Enum.find_index(ids, &(&1 == AtlasWeb.Endpoint))
  end

  test "ClickHouse-disabled instances omit the installer and do not bootstrap self-monitoring" do
    configure(clickhouse_enabled: false, sentry_dsn: nil)

    refute SelfMonitor in child_ids()
    assert :ok = SelfMonitor.install()
    assert SelfMonitor.self_project_id() == nil
    refute Repo.get_by(Project, name: "Atlas")
  end

  test "demo instances omit self-monitoring even with ClickHouse configured" do
    stub(Demo, :enabled?, fn -> true end)

    refute SelfMonitor in child_ids()
    refute IngestRepo in child_ids()
  end

  test "a configured Sentry DSN leaves native capture and the self-project uninstalled" do
    configure(clickhouse_enabled: true, sentry_dsn: "https://public@example.invalid/1")

    assert :ok = SelfMonitor.install()
    assert SelfMonitor.self_project_id() == nil
    refute Repo.get_by(Project, name: "Atlas")
    assert {:error, {:not_found, :atlas_errors_handler}} = :logger.get_handler_config(:atlas_errors_handler)
  end

  test "installed native capture exposes sanitized personal-provider failures as Postgres issues" do
    coalescer = start_supervised!({IssueCoalescer, name: nil, flush_interval_ms: 60_000})
    Sandbox.allow(Repo, self(), coalescer)

    stub(IssueCoalescer, :observe, fn _server, project, fingerprint, event, opts ->
      call_original(IssueCoalescer, :observe, [coalescer, project, fingerprint, event, opts])
    end)

    # Only the ClickHouse write boundary is replaced; Logger, parsing,
    # fingerprinting, the coalescer and Postgres issue queries are real.
    owner = self()

    stub(IngestRepo, :insert_all, fn Event, rows ->
      send(owner, {:ingested, rows})
      {length(rows), nil}
    end)

    # Hold one capture open for the entire native-handler lifetime. Other
    # async captures then cannot remove/restore :default while we attach or
    # detach, which can race OTP's handler dispatch-list updates.
    log =
      capture_log(fn ->
        try do
          installer =
            Atlas.Application.children()
            |> Enum.map(&Supervisor.child_spec(&1, []))
            |> Enum.find(&(&1.id == SelfMonitor))

          %{start: {Task, :start_link, [install]}} = installer

          # Pause the real installer only long enough to grant sandbox/mock access.
          start = fn ->
            receive do
              :install ->
                :ok = install.()
                send(owner, {:installed, SelfMonitor.self_project_id()})
            end
          end

          task = start_supervised!(%{installer | start: {Task, :start_link, [start]}})
          allow(Application, owner, task)
          Sandbox.allow(Repo, owner, task)
          ref = Process.monitor(task)
          send(task, :install)
          assert_receive {:installed, project_id}
          assert_receive {:DOWN, ^ref, :process, ^task, :normal}
          Application.put_env(:atlas, :errors_self_project_id, project_id)

          project = Repo.get!(Project, project_id)
          assert project.name == "Atlas"
          assert project.visibility == :private
          assert [key] = Errors.list_project_keys(project_id)

          assert :ok = SelfMonitor.install()
          assert SelfMonitor.self_project_id() == project_id
          assert [^key] = Errors.list_project_keys(project_id)

          assert {:ok, %{level: :error}} = :logger.get_handler_config(:atlas_errors_handler)
          assert :atlas_errors_handler in :logger.get_handler_ids()

          stub(Req, :post, fn _opts ->
            {:ok, %{status: 503, body: "private upstream body containing setup-token-secret"}}
          end)

          Logger.warning("warning should not become a native issue")
          assert {:error, 503} = PersonalProviders.complete("claude", "setup-token-secret", %{"messages" => []})
          assert {:error, 401} = PersonalProviders.complete("chatgpt", "invalid-token-secret", %{"messages" => []})

          assert_receive {:ingested, [claude_row]}
          assert_receive {:ingested, [chatgpt_row]}
          refute_receive {:ingested, _}

          assert :ok = IssueCoalescer.flush(coalescer)
          issues = Errors.list_issues(project_id: project_id)

          assert Enum.sort(Enum.map(issues, & &1.title)) == [
                   "Orbit personal provider failed: provider=chatgpt category=invalid_account_claim status=401",
                   "Orbit personal provider failed: provider=claude category=http_error status=503"
                 ]

          assert Enum.all?(issues, &(&1.level == :error and &1.event_count == 1 and &1.status == :unresolved))
          assert Enum.sort(Enum.map(issues, & &1.id)) == Enum.sort([claude_row.issue_id, chatgpt_row.issue_id])

          for row <- [claude_row, chatgpt_row] do
            assert row.project_id == project_id
            refute row.payload =~ "secret"
            refute row.payload =~ "private upstream body"
          end
        after
          LoggerHandler.detach()
        end
      end)

    assert log =~ "[error]"
    assert log =~ "provider=claude category=http_error status=503"
    assert log =~ "provider=chatgpt category=invalid_account_claim status=401"
    refute log =~ "private upstream body"
    refute log =~ "setup-token-secret"
    refute log =~ "invalid-token-secret"
  end

  defp child_ids do
    Enum.map(Atlas.Application.children(), &Supervisor.child_spec(&1, []).id)
  end

  defp configure(opts) do
    overrides = %{
      {:atlas, :clickhouse_enabled} => opts[:clickhouse_enabled],
      {:sentry, :dsn} => opts[:sentry_dsn],
      {:atlas, Bufferable} => [write_through_repo: true]
    }

    stub(Application, :get_env, fn
      :atlas, :errors_self_project_id -> Process.get(:self_monitor_test_project_id)
      app, key -> Map.get_lazy(overrides, {app, key}, fn -> call_original(Application, :get_env, [app, key]) end)
    end)

    stub(Application, :get_env, fn app, key, default ->
      Map.get_lazy(overrides, {app, key}, fn -> call_original(Application, :get_env, [app, key, default]) end)
    end)
  end
end
