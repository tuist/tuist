defmodule Tuist.RemoteExecutionTest do
  # Schedulers are globally registered processes whose tasks reach the
  # database and node stubs from outside the test process.
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import TuistTestSupport.Fixtures.ProjectsFixtures

  alias Tuist.Cache
  alias Tuist.FeatureFlags
  alias Tuist.Kura
  alias Tuist.RemoteExecution
  alias Tuist.RemoteExecution.Scheduler
  alias Tuist.RemoteExecution.UsageEvent
  alias Tuist.RemoteExecution.VMs
  alias Tuist.Runners.Allowance
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox

  setup :set_mimic_global

  @image "sha-" <> String.duplicate("a", 40)
  @hash String.duplicate("a", 64)

  setup do
    project = project_fixture()
    stub(FeatureFlags, :bazel_remote_execution_enabled?, fn _ -> true end)
    stub(Cache, :issue_cache_token, fn _project, _opts -> {:ok, "scoped-credential", %{}} end)

    stub(Nodes, :connected_nodes, fn ->
      [
        %{
          name: "reserved-linux",
          execution_deadlines: true,
          execution_slots: 4,
          capacity: %{cpus: 8, memory_bytes: 32 * 1024 * 1024 * 1024},
          templates: [%{name: "bazel", tag: @image, ready: true}],
          disk: %{}
        }
      ]
    end)

    stub(Kura, :runner_cache_endpoint_url, fn _account, :linux -> "https://cache.example" end)
    {:ok, _settings} = configure(project, max_concurrency: 2)

    on_exit(fn ->
      if pid = Scheduler.whereis(project.account_id) do
        try do
          GenServer.stop(pid)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    %{project: project}
  end

  # Limits that hold `max_concurrency` VMs of 2 vCPUs and 4 GB.
  defp configure(project, max_concurrency: vms) do
    {:ok, account} =
      RemoteExecution.update_limits(Repo.reload!(project.account), %{
        remote_execution_vcpus_limit: vms * 2,
        remote_execution_memory_gb_limit: vms * 4
      })

    RemoteExecution.available_settings(account.id)
  end

  # Records every node command and answers exec with `result`, optionally
  # holding the action until the test releases it.
  defp stub_node(result \\ %{"response" => Base.encode64(<<10, 0>>), "cacheable" => true}, opts \\ []) do
    test = self()

    stub(Nodes, :call, fn "reserved-linux", command, args, call_opts ->
      send(test, {:node, command, args})

      case command do
        "exec" when is_map_key(args, :claim) ->
          send(test, {:claim_pending, self()})
          receive do: ({:claim, outcome} -> outcome)

        "exec" ->
          if args.cmd == ["/usr/local/bin/sbx-executor"] do
            run_action(test, call_opts, result, opts)
            {:ok, %{"exit_code" => 0, "duration_ms" => 1_500}}
          else
            {:ok, %{"exit_code" => 0}}
          end

        "delete" ->
          Keyword.get(opts, :delete, {:ok, %{}})

        _ ->
          {:ok, %{}}
      end
    end)
  end

  defp run_action(test, call_opts, result, opts) do
    if opts[:hold] do
      send(test, {:holding, self()})
      receive do: (:release -> :ok)
    end

    call_opts[:on_stream].({:stdout, JSON.encode!(result) <> "\n"})
  end

  defp usage_events(project),
    do: Tuist.ClickHouseRepo.all(from(e in UsageEvent, where: e.account_id == ^project.account_id))

  defp vm_rows(project),
    do: Repo.all(from(s in Sandbox, where: s.account_id == ^project.account_id and s.purpose == :remote_execution))

  defp eventually(fun, attempts \\ 100) do
    cond do
      fun.() ->
        :ok

      attempts == 0 ->
        flunk("condition not reached")

      true ->
        Process.sleep(20)
        eventually(fun, attempts - 1)
    end
  end

  defp submit(project, params \\ %{}, opts \\ [wait: 5_000]),
    do: RemoteExecution.submit(project, Map.merge(%{"hash" => @hash, "size" => 10}, params), opts)

  test "refuses new work once a free account has spent its free minutes", %{project: project} do
    account_id = project.account_id
    stub(Allowance, :exhausted?, fn %{id: ^account_id} -> true end)
    reject(&Nodes.call/4)

    assert {:error, :allowance_exhausted} = submit(project)
    assert {:error, :allowance_exhausted} = RemoteExecution.lease(project, wait: 100)
  end

  test "runs an action in a fresh VM and returns the result before deleting it", %{project: project} do
    stub_node()

    assert {:ok, %{done: true, state: "completed"} = operation} = submit(project)
    assert operation.response == Base.encode64(<<10, 0>>)
    assert %{cacheable: true, action_hash: @hash, action_size: 10, cas_endpoint: "grpcs://cache.example:443"} = operation

    assert_received {:node, "create", %{template_tag: @image, expires_at_unix: expires}}
    assert expires > DateTime.to_unix(DateTime.utc_now())
    assert_received {:node, "exec", %{cmd: ["/usr/local/bin/sbx-executor"], env: env}}
    assert env["SBX_EXECUTION_TOKEN"] == "scoped-credential"

    assert %{"hash" => @hash, "image" => @image, "instance" => instance} = JSON.decode!(env["SBX_EXECUTION_REQUEST"])
    assert instance == project.name

    assert_receive {:node, "delete", %{sandbox_id: used}}
    eventually(fn -> Enum.all?(vm_rows(project), &(&1.id != used)) end)
  end

  test "results that must not be cached are returned without publication details", %{project: project} do
    stub_node(%{"response" => Base.encode64(<<10, 0>>), "cacheable" => false})

    assert {:ok, %{done: true} = operation} = submit(project)
    refute Map.has_key?(operation, :cacheable)
    refute Map.has_key?(operation, :cas_endpoint)
  end

  test "identical in-flight actions of a project share one operation", %{project: project} do
    stub_node(%{"response" => Base.encode64(<<10, 0>>), "cacheable" => true}, hold: true)

    assert {:ok, %{id: id, done: false}} = submit(project, %{}, wait: 0)
    assert {:ok, %{id: ^id}} = submit(project, %{}, wait: 0)
    assert {:ok, %{id: other}} = submit(project, %{"skip_cache" => true}, wait: 0)
    assert other != id

    another_project = project_fixture(account: project.account)
    assert {:ok, %{id: separate}} = submit(another_project, %{}, wait: 0)
    refute separate in [id, other]
    assert {:error, :not_found} = RemoteExecution.await(another_project, id, nil)

    for _ <- 1..3 do
      assert_receive {:holding, task}, 2_000
      send(task, :release)
    end

    assert {:ok, %{id: ^id, done: true}} = RemoteExecution.await(project, id, "executing")
  end

  test "activity lists the project's running and queued actions, not leased VMs or other projects", %{
    project: project
  } do
    assert {:ok, %{running: 0, queued: 0, actions: []}} = RemoteExecution.activity(project)

    stub_node(%{"response" => Base.encode64(<<10, 0>>), "cacheable" => true}, hold: true)

    # Bazel's request metadata only labels the action, so an invalid value is
    # dropped instead of refusing it.
    metadata = %{"invocation_id" => "build-1", "mnemonic" => "CppCompile", "target" => <<0xFF>>}
    assert {:ok, %{done: false}} = submit(project, metadata, wait: 0)
    assert_receive {:holding, running}, 2_000

    # The account's second VM goes to the gateway, which may never use it.
    stub(Nodes, :lookup, fn "reserved-linux" -> {:ok, self(), %{direct_exec_endpoint: "http://10.0.0.1:7071"}} end)
    assert {:ok, %{sandbox_id: _}} = RemoteExecution.lease(project, wait: 5_000)
    assert_receive {:claim_pending, claim}

    assert {:ok, %{state: "queued"}} = submit(project, %{"size" => 11}, wait: 0)
    other_project = project_fixture(account: project.account)
    assert {:ok, %{state: "queued"}} = submit(other_project, %{"size" => 12}, wait: 0)

    assert {:ok, %{running: 1, queued: 1, actions: [first, second], invocations: invocations}} =
             RemoteExecution.activity(project)

    assert %{state: "running", action_digest: "#{@hash}/10", vcpus: 2, memory_gb: 4} = first
    assert %{invocation_id: "build-1", mnemonic: "CppCompile", target: nil} = first
    assert %{state: "queued", action_digest: "#{@hash}/11", invocation_id: nil} = second
    # Kura has not reported the build, so only its actions describe it.
    assert [%{invocation_id: "build-1", command: nil, running: 1, queued: 0}] = invocations
    assert DateTime.compare(first.since, DateTime.utc_now()) != :gt

    send(claim, {:claim, {:ok, %{"exit_code" => 0, "unclaimed" => true}}})
    send(running, :release)

    for _ <- 1..2 do
      assert_receive {:holding, task}, 2_000
      send(task, :release)
    end
  end

  test "operations of a scheduler that is gone are not found", %{project: project} do
    assert {:error, :not_found} = RemoteExecution.await(project, Ecto.UUID.generate(), "queued")
    assert {:error, :not_found} = RemoteExecution.await(project, "not-a-uuid", "queued")
  end

  test "VMs hold account capacity until their deletion is acknowledged", %{project: project} do
    {:ok, settings} = configure(project, max_concurrency: 1)
    assert {:ok, row} = VMs.reserve(project.account_id, settings)
    assert {:error, :busy} = VMs.reserve(project.account_id, settings)

    expect(Nodes, :call, fn _, "delete", _, _ -> {:error, :timeout} end)
    assert {:error, :timeout} = VMs.destroy(%{row | node_name: "reserved-linux"})
    assert {:error, :busy} = VMs.reserve(project.account_id, settings)

    expect(Nodes, :call, fn _, "delete", %{sandbox_id: id}, _ -> {:ok, %{"id" => id}} end)
    assert :ok = VMs.destroy(%{row | node_name: "reserved-linux"})
    assert {:ok, _row} = VMs.reserve(project.account_id, settings)
  end

  test "an action waits while the account's only VM is still being deleted", %{project: project} do
    {:ok, _} = configure(project, max_concurrency: 1)
    # The first VM's deletion is not acknowledged before the second action.
    stub_node(%{"response" => Base.encode64(<<10, 0>>), "cacheable" => true}, delete: {:error, :timeout})
    assert {:ok, %{done: true}} = submit(project)
    assert {:ok, %{done: false, state: "queued", id: id}} = submit(project, %{"size" => 11}, wait: 200)

    stub_node()
    [row] = vm_rows(project)
    send(Scheduler.whereis(project.account_id), {:destroy, row.id})
    assert {:ok, %{id: ^id}} = RemoteExecution.await(project, id, "queued", wait: 5_000)
    assert {:ok, %{id: ^id, done: true}} = RemoteExecution.await(project, id, "executing", wait: 5_000)
    assert_receive {:node, "exec", %{cmd: ["/usr/local/bin/sbx-executor"]}}
  end

  test "an action no node has room for runs as soon as the account frees one", %{project: project} do
    stub(Nodes, :connected_nodes, fn ->
      [
        %{
          name: "reserved-linux",
          execution_deadlines: true,
          execution_slots: 1,
          capacity: %{cpus: 8, memory_bytes: 32 * 1024 * 1024 * 1024},
          templates: [%{name: "bazel", tag: @image, ready: true}],
          disk: %{}
        }
      ]
    end)

    # The account has room for a second VM, but the node is still deleting the first.
    stub_node(%{"response" => Base.encode64(<<10, 0>>), "cacheable" => true}, delete: {:error, :timeout})
    assert {:ok, %{done: true}} = submit(project)
    assert {:ok, %{done: false, state: "queued", id: id}} = submit(project, %{"size" => 11}, wait: 300)

    stub_node()
    [row] = Enum.filter(vm_rows(project), & &1.node_name)
    send(Scheduler.whereis(project.account_id), {:destroy, row.id})
    assert {:ok, %{id: ^id}} = RemoteExecution.await(project, id, "queued", wait: 2_000)

    assert {:ok, %{id: ^id, done: true, queue_waits_ms: waits}} =
             RemoteExecution.await(project, id, "executing", wait: 2_000)

    # The wait for room is charged to the node, not to the account.
    assert waits["node_capacity"] >= 250
    assert Map.keys(waits) -- ["node_capacity", "vm_preparing", "scheduling"] == []
  end

  test "a placement after one that found no room is charged to node capacity", %{project: project} do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    # The first placement finds no room; the next one takes 300 ms to find it,
    # the way a carve-out growth does.
    stub(Capacity, :place_execution, fn sandbox, tag ->
      case Agent.get_and_update(attempts, &{&1, &1 + 1}) do
        0 ->
          {:error, :no_capacity}

        _ ->
          Process.sleep(300)
          Mimic.call_original(Capacity, :place_execution, [sandbox, tag])
      end
    end)

    stub_node()
    assert {:ok, %{done: false, state: "queued", id: id}} = submit(project, %{}, wait: 100)
    send(Scheduler.whereis(project.account_id), {:remote_execution_room, "reserved-linux"})
    assert {:ok, %{id: ^id}} = RemoteExecution.await(project, id, "queued", wait: 3_000)

    assert {:ok, %{id: ^id, done: true, queue_waits_ms: waits}} =
             RemoteExecution.await(project, id, "executing", wait: 3_000)

    assert waits["node_capacity"] >= 300
    assert Map.get(waits, "vm_preparing", 0) < 100
  end

  test "an action no node has room for runs as soon as another account frees one", %{project: project} do
    stub(Nodes, :connected_nodes, fn ->
      [
        %{
          name: "reserved-linux",
          execution_deadlines: true,
          execution_slots: 1,
          capacity: %{cpus: 8, memory_bytes: 32 * 1024 * 1024 * 1024},
          templates: [%{name: "bazel", tag: @image, ready: true}],
          disk: %{}
        }
      ]
    end)

    # Another account's VM holds the node's only slot.
    other = project_fixture()
    {:ok, settings} = configure(other, max_concurrency: 1)
    {:ok, vm} = VMs.reserve(other.account_id, settings)
    Repo.update_all(from(s in Sandbox, where: s.id == ^vm.id), set: [node_name: "reserved-linux", state: :running])

    stub_node()
    assert {:ok, %{done: false, state: "queued", id: id}} = submit(project, %{}, wait: 300)

    assert :ok = VMs.destroy(%{vm | node_name: "reserved-linux"})

    # Well before the scheduler's 5 s tick.
    assert {:ok, %{id: ^id}} = RemoteExecution.await(project, id, "queued", wait: 2_000)
    assert {:ok, %{id: ^id, done: true}} = RemoteExecution.await(project, id, "executing", wait: 2_000)
  end

  test "the warm pool follows demand below its ceiling", %{project: project} do
    {:ok, _} = configure(project, max_concurrency: 8)
    stub_node()
    assert {:ok, %{done: true}} = submit(project)

    # One recent action needs one ready VM plus one in reserve, not the ceiling.
    eventually(fn -> length(vm_rows(project)) == 2 end)
    Process.sleep(300)
    assert length(vm_rows(project)) == 2
  end

  test "a warm VM is kept ready and taken by the next action", %{project: project} do
    {:ok, _} = configure(project, max_concurrency: 1)
    stub_node()
    assert {:ok, %{done: true}} = submit(project)
    assert_received {:node, "exec", %{cmd: ["/usr/local/bin/sbx-executor"], sandbox_id: used}}

    # The used VM is deleted first: the account has room for one.
    eventually(fn ->
      match?([%Sandbox{state: :running, id: id}] when id != used, vm_rows(project))
    end)

    [warm] = vm_rows(project)
    flush_node_messages()
    assert {:ok, %{done: true}} = submit(project, %{"size" => 11})
    assert_received {:node, "exec", %{cmd: ["/usr/local/bin/sbx-executor"], sandbox_id: id}}
    assert id == warm.id
  end

  test "an unavailable account cannot submit", %{project: project} do
    stub(FeatureFlags, :bazel_remote_execution_enabled?, fn _ -> false end)
    assert {:error, :unavailable} = submit(project)
    assert Scheduler.whereis(project.account_id) == nil
  end

  test "accounts execute with default limits and the deployment's image, cache and endpoint" do
    stub(Tuist.Environment, :remote_execution_endpoint, fn -> "grpcs://execution.example" end)
    stub(Kura, :runner_cache_endpoint_url, fn _account, :linux -> "http://kura.tuist.svc:4000" end)
    account = project_fixture().account

    # 16 vCPUs and 32 GB hold eight VMs of 2 vCPUs and 4 GB.
    assert {:ok,
            %{
              max_concurrency: 8,
              image_tag: @image,
              cas_endpoint: "grpc://kura.tuist.svc:4000",
              executor_endpoint: "grpcs://execution.example"
            }} = RemoteExecution.available_settings(account.id)

    stub(Kura, :runner_cache_endpoint_url, fn _account, :linux -> nil end)
    assert {:error, :unavailable} = RemoteExecution.available_settings(account.id)

    stub(Kura, :runner_cache_endpoint_url, fn _account, :linux -> "https://cache.example" end)
    stub(Nodes, :connected_nodes, fn -> [] end)
    assert {:error, :unavailable} = RemoteExecution.available_settings(account.id)
  end

  test "the scarcer of the vCPU and memory limits bounds the account's VMs", %{project: project} do
    {:ok, account} =
      RemoteExecution.update_limits(project.account, %{
        remote_execution_vcpus_limit: 8,
        remote_execution_memory_gb_limit: 7
      })

    assert {:ok, %{max_concurrency: 1} = settings} = RemoteExecution.available_settings(account.id)
    assert {:ok, _row} = VMs.reserve(account.id, settings)
    assert {:error, :busy} = VMs.reserve(account.id, settings)

    assert {:error, changeset} =
             RemoteExecution.update_limits(account, %{remote_execution_vcpus_limit: 1})

    assert %{remote_execution_vcpus_limit: [_]} = errors_on(changeset)
  end

  test "inputs the gateway prefetched reach the action's VM", %{project: project} do
    stub_node()

    assert {:ok, %{done: true}} = submit(project, %{"inputs" => "cHJlZmV0Y2hlZA=="})
    assert_received {:node, "exec", %{cmd: ["/usr/local/bin/sbx-executor"], env: env}}
    assert %{"inputs" => "cHJlZmV0Y2hlZA=="} = JSON.decode!(env["SBX_EXECUTION_REQUEST"])
  end

  describe "VM sizes" do
    test "an action that asks for more memory runs in a VM of that size outside the warm pool", %{project: project} do
      stub_node()

      assert {:ok, %{done: true, code: 0}} = submit(project, %{"memory_gb" => 8})
      assert_received {:node, "create", %{vcpus: 4, memory_mb: 8192, sandbox_id: large}}
      assert_received {:node, "exec", %{cmd: ["/usr/local/bin/sbx-executor"], sandbox_id: ^large, env: env}}
      assert %{"memory_gb" => 8} = JSON.decode!(env["SBX_EXECUTION_REQUEST"])

      # The warm pool refills with default VMs once the large one is deleted,
      # which leave the account no room for a warm large one.
      eventually(fn ->
        rows = vm_rows(project)
        rows != [] and Enum.all?(rows, &(&1.memory_mb == 4096 and &1.id != large))
      end)
    end

    test "a size the account just used keeps one VM of it warm beside the default ones", %{project: project} do
      {:ok, _} = configure(project, max_concurrency: 8)
      stub_node()

      assert {:ok, %{done: true}} = submit(project, %{"memory_gb" => 8})
      assert_received {:node, "create", %{memory_mb: 8192, sandbox_id: used}}

      eventually(fn ->
        rows = vm_rows(project)
        Enum.count(rows, &(&1.memory_mb == 8192 and &1.id != used)) == 1 and Enum.any?(rows, &(&1.memory_mb == 4096))
      end)

      # One, not the number of recent actions of that size.
      Process.sleep(300)
      assert project |> vm_rows() |> Enum.filter(&(&1.memory_mb == 8192 and &1.id != used)) |> length() == 1
    end

    test "a size used before the scheduler started is warmed with the first build's pool", %{project: project} do
      {:ok, _} = configure(project, max_concurrency: 8)

      Tuist.IngestRepo.insert_all(UsageEvent, [
        %{
          id: UUIDv7.generate(),
          account_id: project.account_id,
          project_id: project.id,
          sandbox_id: UUIDv7.generate(),
          mode: "scheduled",
          vcpus: 4,
          memory_mb: 8192,
          duration_ms: 20_000,
          inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3_600)
        }
      ])

      stub_node()
      assert {:ok, %{done: true}} = submit(project)
      assert_receive {:node, "create", %{memory_mb: 8192}}, 2_000
    end

    test "an action that asks for 2 GB runs in a 1 vCPU VM", %{project: project} do
      stub_node()

      assert {:ok, %{done: true, code: 0}} = submit(project, %{"memory_gb" => 2})
      assert_received {:node, "create", %{vcpus: 1, memory_mb: 2048, sandbox_id: small}}
      assert_received {:node, "exec", %{cmd: ["/usr/local/bin/sbx-executor"], sandbox_id: ^small}}
    end

    test "a larger action takes the room idle warm VMs hold", %{project: project} do
      # 4 vCPUs and 8 GB: two warm default VMs fill the account.
      stub_node()
      assert {:ok, %{done: true}} = submit(project)
      eventually(fn -> match?([%{state: :running}, %{state: :running}], vm_rows(project)) end)
      flush_node_messages()

      assert {:ok, %{done: true, code: 0}} = submit(project, %{"size" => 11, "memory_gb" => 8})
      assert_received {:node, "create", %{memory_mb: 8192}}
    end

    test "an action larger than the account's limits fails without a VM", %{project: project} do
      stub_node()

      assert {:ok, %{done: true, code: 9, message: message}} = submit(project, %{"memory_gb" => 16})
      assert message =~ "larger VM"
      refute_received {:node, "create", %{memory_mb: 16_384}}
    end

    test "a larger action waits for the room a running action holds", %{project: project} do
      # 4 vCPUs and 8 GB, with a default action holding half.
      stub_node(%{"response" => Base.encode64(<<10, 0>>), "cacheable" => true}, hold: true)
      first = Task.async(fn -> submit(project) end)
      assert_receive {:holding, held}, 5_000

      assert {:ok, %{done: false, state: "queued", id: large}} =
               submit(project, %{"size" => 11, "memory_gb" => 8}, wait: 300)

      refute_received {:node, "create", %{memory_mb: 8192}}

      stub_node()
      send(held, :release)
      assert {:ok, %{done: true}} = Task.await(first)
      assert {:ok, %{id: ^large}} = RemoteExecution.await(project, large, "queued", wait: 5_000)

      assert {:ok, %{id: ^large, done: true, code: 0, queue_waits_ms: waits}} =
               RemoteExecution.await(project, large, "executing", wait: 5_000)

      # Waiting for the running action's room is the account's limit, then its VM.
      assert waits["account_limit"] >= 250
      assert waits["vm_preparing"] > 0
      refute Map.has_key?(waits, "node_capacity")
      assert_received {:node, "create", %{memory_mb: 8192}}
    end
  end

  test "invalid requests are rejected before scheduling", %{project: project} do
    assert {:error, :invalid_request} = submit(project, %{"memory_gb" => 6})
    assert {:error, :invalid_request} = submit(project, %{"memory_gb" => "8"})
    assert {:error, :invalid_request} = submit(project, %{"hash" => "short"})
    assert {:error, :invalid_request} = submit(project, %{"size" => -1})
    assert {:error, :invalid_request} = submit(project, %{"skip_cache" => "yes"})
    assert {:error, :invalid_request} = submit(project, %{"inputs" => 42})
    assert {:error, :invalid_request} = submit(project, %{"inputs" => String.duplicate("a", 400_000)})
  end

  test "reaping deletes only VMs whose lease lapsed", %{project: project} do
    {:ok, settings} = configure(project, max_concurrency: 2)
    {:ok, lapsed} = VMs.reserve(project.account_id, settings)
    {:ok, live} = VMs.reserve(project.account_id, settings)

    lapsed
    |> Ecto.Changeset.change(
      node_name: "reserved-linux",
      execution_lease_expires_at: DateTime.add(DateTime.utc_now(:second), -60)
    )
    |> Repo.update!()

    stub_node()
    RemoteExecution.maintain()

    assert_received {:node, "delete", %{sandbox_id: id}}
    assert id == lapsed.id
    assert [%{id: live_id}] = vm_rows(project)
    assert live_id == live.id
  end

  test "renewal extends leases of existing rows only", %{project: project} do
    {:ok, settings} = configure(project, max_concurrency: 2)
    {:ok, row} = VMs.reserve(project.account_id, settings)
    short = DateTime.add(DateTime.utc_now(:second), 5)
    row |> Ecto.Changeset.change(execution_lease_expires_at: short) |> Repo.update!()

    assert [id] = VMs.renew([row.id, Ecto.UUID.generate()])
    assert id == row.id
    assert DateTime.after?(Repo.get!(Sandbox, row.id).execution_lease_expires_at, short)
  end

  describe "telemetry" do
    setup do
      test = self()
      handler = "remote-execution-#{inspect(test)}"

      events = [
        [:tuist, :remote_execution, :submission],
        [:tuist, :remote_execution, :operation],
        [:tuist, :remote_execution, :prepare],
        [:tuist, :remote_execution, :lease]
      ]

      :telemetry.attach_many(
        handler,
        events,
        fn event, measurements, metadata, _ -> send(test, {:telemetry, event, measurements, metadata}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)
    end

    test "a completed action reports its submission, preparation and outcome", %{project: project} do
      stub_node()

      assert {:ok, %{done: true}} = submit(project)

      assert_receive {:telemetry, [:tuist, :remote_execution, :submission], %{count: 1}, %{outcome: "accepted"}}
      assert_receive {:telemetry, [:tuist, :remote_execution, :prepare], %{duration: prepare}, %{outcome: "ok"}}
      assert prepare >= 0

      assert_receive {:telemetry, [:tuist, :remote_execution, :operation], %{duration: duration, queue_time: queue},
                      %{outcome: "ok"}}

      assert duration >= queue and queue >= 0
    end

    test "joining an in-flight action and a full queue are reported", %{project: project} do
      {:ok, _} = configure(project, max_concurrency: 1)
      stub_node(%{"response" => Base.encode64(<<10, 0>>), "cacheable" => true}, hold: true)

      assert {:ok, %{done: false}} = submit(project, %{}, wait: 0)
      assert {:ok, %{done: false}} = submit(project, %{}, wait: 0)
      assert_receive {:holding, _task}, 2_000
      for size <- 11..26, do: assert({:ok, %{done: false}} = submit(project, %{"size" => size}, wait: 0))
      assert {:error, :queue_full} = submit(project, %{"size" => 27}, wait: 0)

      assert_receive {:telemetry, [:tuist, :remote_execution, :submission], _, %{outcome: "deduplicated"}}
      assert_receive {:telemetry, [:tuist, :remote_execution, :submission], _, %{outcome: "queue_full"}}
    end

    test "failed actions report their status code", %{project: project} do
      stub_node(%{"unexpected" => true})

      assert {:ok, %{done: true}} = submit(project)
      assert_receive {:telemetry, [:tuist, :remote_execution, :operation], _, %{outcome: "internal"}}
    end

    test "leases report whether the gateway claimed them", %{project: project} do
      stub(Nodes, :lookup, fn "reserved-linux" -> {:ok, self(), %{direct_exec_endpoint: "http://10.0.0.1:7071"}} end)
      stub_node()

      assert {:ok, %{}} = RemoteExecution.lease(project, wait: 5_000)
      assert_receive {:claim_pending, first}
      send(first, {:claim, {:ok, %{"exit_code" => 0, "unclaimed" => true}}})
      assert_receive {:telemetry, [:tuist, :remote_execution, :lease], %{count: 1}, %{outcome: "unclaimed"}}

      assert {:ok, %{}} = RemoteExecution.lease(project, wait: 5_000)
      assert_receive {:claim_pending, second}
      send(second, {:claim, {:ok, %{"exit_code" => 0}}})
      assert_receive {:telemetry, [:tuist, :remote_execution, :lease], %{count: 1}, %{outcome: "claimed"}}
    end
  end

  describe "leases" do
    setup do
      stub(Nodes, :lookup, fn "reserved-linux" -> {:ok, self(), %{direct_exec_endpoint: "http://10.0.0.1:7071"}} end)
      :ok
    end

    test "a lease hands a prepared VM to the gateway through a claimed exec", %{project: project} do
      stub_node()

      assert {:ok, lease} = RemoteExecution.lease(project, wait: 5_000)
      assert %{endpoint: "http://10.0.0.1:7071", image: @image, cas_endpoint: "grpcs://cache.example:443"} = lease
      assert lease.expires_in_ms > 0
      assert_receive {:claim_pending, node_call}
      assert_received {:node, "exec", %{sandbox_id: id, env: env, claim: claim}}
      assert id == lease.sandbox_id
      assert env["SBX_EXECUTION_TOKEN"] == "scoped-credential"
      refute Map.has_key?(env, "SBX_EXECUTION_REQUEST")
      assert claim.env == "SBX_EXECUTION_REQUEST"
      assert claim.nonce_sha256 == Base.encode16(:crypto.hash(:sha256, Base.decode64!(lease.nonce)), case: :lower)

      send(node_call, {:claim, {:ok, %{"exit_code" => 0}}})
      assert_receive {:node, "delete", %{sandbox_id: ^id}}
      eventually(fn -> Enum.all?(vm_rows(project), &(&1.id != id)) end)
    end

    test "an unclaimed lease returns its VM untouched to the next action", %{project: project} do
      stub_node()

      assert {:ok, %{sandbox_id: id}} = RemoteExecution.lease(project, wait: 5_000)
      assert_receive {:claim_pending, node_call}
      send(node_call, {:claim, {:ok, %{"exit_code" => 0, "unclaimed" => true}}})

      assert {:ok, %{done: true}} = submit(project)

      assert_received {:node, "exec",
                       %{cmd: ["/usr/local/bin/sbx-executor"], sandbox_id: ^id, env: %{"SBX_EXECUTION_REQUEST" => _}}}
    end

    test "scheduled and claimed leased actions record the node-measured execution time", %{project: project} do
      stub_node()

      assert {:ok, %{done: true}} = submit(project)

      eventually(fn ->
        match?([%{mode: "scheduled", duration_ms: 1_500, vcpus: 2, memory_mb: 4096}], usage_events(project))
      end)

      assert {:ok, %{sandbox_id: id}} = RemoteExecution.lease(project, wait: 5_000)
      assert_receive {:claim_pending, node_call}
      send(node_call, {:claim, {:ok, %{"exit_code" => 0, "duration_ms" => 2_500}}})

      eventually(fn ->
        Enum.any?(usage_events(project), &(&1.mode == "leased" and &1.duration_ms == 2_500 and &1.sandbox_id == id))
      end)
    end

    test "an unclaimed lease records no usage, only the action that later took its VM", %{project: project} do
      stub_node()

      assert {:ok, %{}} = RemoteExecution.lease(project, wait: 5_000)
      assert_receive {:claim_pending, node_call}
      send(node_call, {:claim, {:ok, %{"exit_code" => 0, "unclaimed" => true}}})
      assert {:ok, %{done: true}} = submit(project)

      eventually(fn -> usage_events(project) != [] end)
      assert [%{mode: "scheduled"}] = usage_events(project)
    end

    test "a lease that finds no VM in time returns none", %{project: project} do
      {:ok, _} = configure(project, max_concurrency: 1)
      stub_node(%{"response" => Base.encode64(<<10, 0>>), "cacheable" => true}, hold: true)
      assert {:ok, %{done: false}} = submit(project, %{}, wait: 0)
      assert_receive {:holding, _task}, 2_000

      assert {:ok, nil} = RemoteExecution.lease(project, wait: 100)
    end

    test "nodes without a direct endpoint grant no leases", %{project: project} do
      stub(Nodes, :lookup, fn "reserved-linux" -> {:ok, self(), %{}} end)
      stub_node()

      assert {:error, :unsupported} = RemoteExecution.lease(project, wait: 5_000)
    end
  end

  defp flush_node_messages do
    receive do
      {:node, _, _} -> flush_node_messages()
    after
      0 -> :ok
    end
  end
end
