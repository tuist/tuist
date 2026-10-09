defmodule TuistWeb.PublicOverviewCacheTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Phoenix.LiveView.Async
  alias Phoenix.LiveView.Socket
  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.Bundles
  alias Tuist.KeyValueStore
  alias Tuist.KeyValueStore.LoadLimiter
  alias Tuist.Projects
  alias TuistWeb.PublicOverviewCache
  alias TuistWeb.XcodeOverviewLive

  setup do
    project = %{
      id: System.unique_integer([:positive]),
      name: "project",
      account: %{name: "account", visibility: :private, organization_id: nil},
      build_system: :xcode,
      visibility: :public
    }

    values = start_supervised!({Agent, fn -> %{} end})
    pool = String.to_atom("public_overview_test_#{System.unique_integer([:positive])}")
    start_supervised!({LoadLimiter, [name: pool]})

    stub(KeyValueStore, :get, fn key, opts ->
      assert opts[:persist_across_deployments]
      Agent.get(values, &Map.get(&1, key))
    end)

    stub(KeyValueStore, :put, fn key, value, opts ->
      assert opts[:ttl] == to_timeout(minute: 10)
      assert opts[:persist_across_deployments]
      Agent.update(values, &Map.put(&1, key, value))
      {:ok, true}
    end)

    stub(LoadLimiter, :run, fn _name, key, loader, timeout ->
      Mimic.call_original(LoadLimiter, :run, [pool, key, loader, timeout])
    end)

    stub(Projects, :get_project_by_account_and_project_handles, fn _, _ -> project end)
    stub(Authorization, :authorize, fn :dashboard_read, _, _ -> :ok end)
    socket = %Socket{assigns: %{__changed__: %{}, selected_project: project, cached_public_overview: true}}
    %{socket: socket, project: project, values: values, pool: pool}
  end

  test "only public roots with ignored tracking parameters are cacheable", %{project: project} do
    assert PublicOverviewCache.public_root?(project, "https://tuist.dev/account/project")
    assert PublicOverviewCache.public_root?(project, "https://tuist.dev/account/project/?utm_source=slack&gclid=123")

    for path <- [
          "/account/project/analytics",
          "/account/project/builds",
          "/account/project?analytics-date-range=last-30-days",
          "/account/project?bundle-size-app=App",
          "/account/project?unknown=1",
          "/account/other"
        ] do
      refute PublicOverviewCache.public_root?(project, "https://tuist.dev" <> path)
    end

    refute PublicOverviewCache.public_root?(%{project | visibility: :private}, "https://tuist.dev/account/project")
  end

  test "SSO-enforced private accounts are not anonymously crawlable", %{project: project} do
    project = %{project | account: %{name: "account", visibility: :private, organization_id: 1}}
    organization = %{sso_enforced: true, sso_provider: :okta}
    stub(Accounts, :get_organization_by_id, fn 1, [preload: []] -> {:ok, organization} end)
    refute PublicOverviewCache.public_root?(project, "https://tuist.dev/account/project")

    project = %{project | account: %{project.account | visibility: :public}}
    assert PublicOverviewCache.public_root?(project, "https://tuist.dev/account/project")
  end

  test "the Cachex fallback has an active bounded eviction policy" do
    {:ok, {_flags, children}} = PublicOverviewCache.init([])
    %{start: {Cachex, :start_link, [[_name, opts]]}} = Enum.find(children, &(&1.id == Cachex))
    name = String.to_atom("overview_values_#{System.unique_integer([:positive])}")
    start_supervised!({Cachex, [name, opts]})
    for key <- 1..257, do: Cachex.put(name, key, key)
    wait_for_eviction(name)
    assert Cachex.size(name) <= 256
  end

  @tag capture_log: true
  test "oversized values are returned but not retained", %{socket: socket, values: values} do
    large = String.duplicate("x", 128 * 1_024)
    assert PublicOverviewCache.load(socket, :apps, fn -> large end) == {:ok, large}
    assert Agent.get(values, &map_size/1) == 0
  end

  test "resolves the default overview before the first HTML render and reuses cached data", %{socket: socket} do
    loaded =
      socket
      |> PublicOverviewCache.assign_async([:metric, :recent], fn -> {:ok, %{metric: 42, recent: ["run"]}} end)
      |> PublicOverviewCache.resolve_pending()

    assert loaded.assigns.metric.ok?
    assert loaded.assigns.metric.result == 42
    assert loaded.assigns.recent.result == ["run"]
    refute loaded.assigns.metric.loading

    cached =
      socket
      |> PublicOverviewCache.assign_async([:metric, :recent], fn -> flunk("must reuse cached data") end)
      |> PublicOverviewCache.resolve_pending()

    assert cached.assigns.metric.result == 42
  end

  test "private and filtered requests retain connected-only asynchronous loading", %{socket: socket} do
    socket = %{socket | assigns: Map.put(socket.assigns, :cached_public_overview, false)}

    socket =
      socket
      |> PublicOverviewCache.assign_async(:metric, fn -> flunk("must not load during a private dead render") end)
      |> PublicOverviewCache.resolve_pending()

    refute socket.assigns.metric.ok?
    assert socket.assigns.metric.loading
  end

  test "failed data remains failed and is not cached", %{socket: socket} do
    failed =
      socket
      |> PublicOverviewCache.assign_async(:metric, fn -> {:error, :unavailable} end)
      |> PublicOverviewCache.resolve_pending()

    assert failed.assigns.metric.failed == {:error, :unavailable}
    refute failed.assigns.metric.ok?

    recovered =
      socket
      |> PublicOverviewCache.assign_async(:metric, fn -> {:ok, %{metric: 42}} end)
      |> PublicOverviewCache.resolve_pending()

    assert recovered.assigns.metric.result == 42
  end

  test "synchronous app options use the same bounded cache", %{socket: socket} do
    assert PublicOverviewCache.load(socket, :apps, fn -> ["App"] end) == {:ok, ["App"]}
    assert PublicOverviewCache.load(socket, :apps, fn -> flunk("must reuse app options") end) == {:ok, ["App"]}
  end

  for project_count <- [1, 3] do
    @project_count project_count
    test "eight-widget overviews for #{@project_count} cold projects recover without exceeding admission", %{
      socket: socket,
      project: project
    } do
      pool = String.to_atom("slow_overview_#{System.unique_integer([:positive])}")
      start_supervised!({LoadLimiter, [name: pool, queue_timeout: 10, load_timeout: 10]})
      activity = start_supervised!({Agent, fn -> %{running: 0, peak: 0} end}, id: :activity)

      stub(LoadLimiter, :run, fn _name, key, loader, timeout ->
        Mimic.call_original(LoadLimiter, :run, [pool, key, loader, timeout])
      end)

      projects = Enum.map(1..@project_count, fn index -> %{project | id: project.id + index, name: "project#{index}"} end)

      stub(Projects, :get_project_by_account_and_project_handles, fn _, name ->
        Enum.find(projects, &(&1.name == name))
      end)

      groups = [
        [:binary_cache_hit_rate_analytics],
        [:selective_testing_analytics],
        [:build_analytics, :builds_duration_analytics],
        [:test_analytics],
        [:recent_test_runs, :failed_test_runs_count, :passed_test_runs_count],
        [:latest_app_previews],
        [:recent_build_runs, :passed_build_runs_count, :failed_build_runs_count],
        [:bundle_size_apps, :bundle_size_analytics]
      ]

      loader = fn keys ->
        fn ->
          Agent.update(activity, fn state ->
            %{state | running: state.running + 1, peak: max(state.peak, state.running + 1)}
          end)

          Process.sleep(20)
          Agent.update(activity, &%{&1 | running: &1.running - 1})
          {:ok, Map.new(keys, &{&1, 42})}
        end
      end

      sockets = Enum.map(projects, &%{socket | assigns: Map.put(socket.assigns, :selected_project, &1)})

      initial =
        sockets
        |> Task.async_stream(
          fn socket ->
            groups
            |> Enum.reduce(socket, &PublicOverviewCache.assign_async(&2, &1, loader.(&1)))
            |> PublicOverviewCache.resolve_pending()
          end,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, socket} -> socket end)

      assert Enum.any?(initial, fn socket -> Enum.any?(List.flatten(groups), &socket.assigns[&1].failed) end)

      connected =
        Enum.map(sockets, fn socket ->
          Task.async(fn ->
            socket =
              Enum.reduce(
                groups,
                %{socket | transport_pid: self()},
                &PublicOverviewCache.assign_async(&2, &1, loader.(&1))
              )

            Enum.reduce(groups, socket, fn _group, socket ->
              assert_receive {:phoenix, :async_result, {kind, {ref, cid, keys, result}}}, 20_000
              Async.handle_async(socket, cid, kind, keys, ref, result)
            end)
          end)
        end)

      for task <- connected do
        socket = Task.await(task, 25_000)
        for key <- List.flatten(groups), do: assert(socket.assigns[key].result == 42)
      end

      assert Agent.get(activity, & &1.peak) <= 2
    end
  end

  for {project_count, delay} <- [{1, 1_100}, {3, 500}] do
    @project_count project_count
    @delay delay
    test "initial HTML resolves eight slow widgets for #{@project_count} cold projects", %{
      socket: socket,
      project: project
    } do
      {:ok, {_flags, children}} = PublicOverviewCache.init([])
      %{start: {LoadLimiter, :start_link, [opts]}} = Enum.find(children, &(&1.id == PublicOverviewCache.Loaders))
      pool = String.to_atom("cold_overview_#{System.unique_integer([:positive])}")
      start_supervised!({LoadLimiter, Keyword.put(opts, :name, pool)})
      activity = start_supervised!({Agent, fn -> %{running: 0, peak: 0} end}, id: :activity)

      stub(LoadLimiter, :run, fn _name, key, loader, timeout ->
        Mimic.call_original(LoadLimiter, :run, [pool, key, loader, timeout])
      end)

      sockets =
        Enum.map(1..@project_count, fn index ->
          %{socket | assigns: Map.put(socket.assigns, :selected_project, %{project | id: project.id + index})}
        end)

      initial =
        Task.async_stream(
          sockets,
          fn socket ->
            1..8
            |> Enum.reduce(socket, fn index, socket ->
              key = String.to_atom("widget_#{index}")

              PublicOverviewCache.assign_async(socket, key, fn ->
                Agent.update(activity, fn state ->
                  %{state | running: state.running + 1, peak: max(state.peak, state.running + 1)}
                end)

                Process.sleep(@delay)
                Agent.update(activity, &%{&1 | running: &1.running - 1})
                {:ok, %{key => 42}}
              end)
            end)
            |> PublicOverviewCache.resolve_pending()
          end,
          timeout: :infinity
        )

      for {:ok, socket} <- initial, index <- 1..8 do
        result = socket.assigns[String.to_atom("widget_#{index}")]
        assert result.ok?
        assert result.result == 42
        refute result.failed
      end

      assert Agent.get(activity, & &1.peak) == 2
    end
  end

  test "the bundle loader retries failed app options inside its existing admission slot", %{
    socket: socket,
    project: project
  } do
    expect(LoadLimiter, :run, fn _name, _key, _loader, _timeout -> {:error, :overloaded} end)
    expect(Bundles, :project_app_bundle_options, fn ^project -> [%{name: "App", supported_platforms: [:ios]}] end)

    expect(Bundles, :project_bundle_install_size_analytics, fn ^project, _opts ->
      [%{date: "2026-10-08", bundle_install_size: 1_024}]
    end)

    socket = XcodeOverviewLive.assign_handle_params(socket, %{}, "/account/project")
    [{keys, loader} | _other_widgets] = socket.private.public_overview_loaders
    assert keys == [:bundle_size_apps, :bundle_size_analytics]
    assert {:ok, %{bundle_size_apps: ["App"], bundle_size_analytics: [["2026-10-08", 1_024]]}} = loader.()
  end

  @tag capture_log: true
  test "a storage outage cannot bypass admission", %{socket: socket} do
    stub(KeyValueStore, :get, fn _, _ -> exit(:cache_down) end)
    expect(LoadLimiter, :run, fn _name, _key, _loader, _timeout -> {:error, :unavailable} end)
    assert PublicOverviewCache.load(socket, :apps, fn -> flunk("must not bypass admission") end) == {:error, :unavailable}
  end

  test "an admitted miss rechecks shared storage before executing a loader", %{socket: socket} do
    expect(KeyValueStore, :get, fn _key, _opts -> nil end)
    expect(KeyValueStore, :get, fn _key, _opts -> %{apps: ["filled by another pod"]} end)

    assert PublicOverviewCache.load(socket, :apps, fn -> flunk("must double-check") end) ==
             {:ok, ["filled by another pod"]}
  end

  test "connected loads recover from saturation through the same admitted pool", %{socket: socket} do
    expect(LoadLimiter, :run, fn _name, _key, _loader, _timeout -> {:error, :overloaded} end)
    socket = %{socket | transport_pid: self()}
    socket = PublicOverviewCache.assign_async(socket, :metric, fn -> {:ok, %{metric: 42}} end)
    assert_receive {:phoenix, :async_result, {kind, {ref, cid, keys, result}}}, 2_000
    socket = Async.handle_async(socket, cid, kind, keys, ref, result)
    assert socket.assigns.metric.ok?
    assert socket.assigns.metric.result == 42
  end

  test "recovery cannot cache an old loader under a reused project handle", %{
    socket: socket,
    project: project,
    values: values
  } do
    expect(LoadLimiter, :run, fn _name, _key, _loader, _timeout -> {:error, :overloaded} end)
    stub(Projects, :get_project_by_account_and_project_handles, fn _, _ -> %{project | id: project.id + 1} end)

    socket =
      PublicOverviewCache.assign_async(%{socket | transport_pid: self()}, :metric, fn ->
        flunk("must not run stale loader")
      end)

    assert_receive {:phoenix, :async_result, {kind, {ref, cid, keys, result}}}, 2_000
    socket = Async.handle_async(socket, cid, kind, keys, ref, result)
    assert socket.assigns.metric.failed == {:error, :forbidden}
    assert Agent.get(values, &map_size/1) == 0
  end

  test "cached values bypass miss admission entirely", %{socket: socket, values: values} do
    assert PublicOverviewCache.load(socket, :apps, fn -> ["App"] end) == {:ok, ["App"]}
    assert Agent.get(values, &map_size/1) == 1
    reject(LoadLimiter, :run, 4)
    assert PublicOverviewCache.load(socket, :apps, fn -> flunk("must use KeyValueStore") end) == {:ok, ["App"]}
  end

  defp wait_for_eviction(cache, attempts \\ 100) do
    if Cachex.size(cache) <= 256 do
      :ok
    else
      assert attempts > 0
      Process.sleep(5)
      wait_for_eviction(cache, attempts - 1)
    end
  end

  test "cache keys isolate build systems and renamed projects", %{socket: socket, project: project} do
    assert PublicOverviewCache.load(socket, :apps, fn -> ["App"] end) == {:ok, ["App"]}

    for changed <- [
          %{project | build_system: :gradle},
          %{project | name: "renamed"},
          %{project | account: %{name: "renamed"}}
        ] do
      socket = %{socket | assigns: Map.put(socket.assigns, :selected_project, changed)}
      assert PublicOverviewCache.load(socket, :apps, fn -> ["Different"] end) == {:ok, ["Different"]}
    end
  end
end
