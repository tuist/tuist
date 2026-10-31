defmodule Tuist.RemoteExecutionTest do
  # Schedulers are globally registered processes whose tasks reach the
  # database and node stubs from outside the test process.
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import TuistTestSupport.Fixtures.ProjectsFixtures

  alias Tuist.Cache
  alias Tuist.FeatureFlags
  alias Tuist.RemoteExecution
  alias Tuist.RemoteExecution.Scheduler
  alias Tuist.RemoteExecution.VMs
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

    {:ok, _settings} = configure(project, max_concurrency: 2, warm_pool_size: 0)

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

  defp configure(project, attrs) do
    RemoteExecution.configure(
      project.account,
      Map.merge(
        %{
          node_names: ["reserved-linux"],
          image_tag: @image,
          cas_endpoint: "grpcs://cache.example",
          executor_endpoint: "grpcs://execution.example"
        },
        Map.new(attrs)
      )
    )
  end

  # Records every node command and answers exec with `result`, optionally
  # holding the action until the test releases it.
  defp stub_node(result \\ %{"response" => Base.encode64(<<10, 0>>), "cacheable" => true}, opts \\ []) do
    test = self()

    stub(Nodes, :call, fn "reserved-linux", command, args, call_opts ->
      send(test, {:node, command, args})

      case command do
        "exec" ->
          if args.cmd == ["/usr/local/bin/sbx-executor"], do: run_action(test, call_opts, result, opts)
          {:ok, %{"exit_code" => 0}}

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

  test "runs an action in a fresh VM and returns the result before deleting it", %{project: project} do
    stub_node()

    assert {:ok, %{done: true, state: "completed"} = operation} = submit(project)
    assert operation.response == Base.encode64(<<10, 0>>)
    assert %{cacheable: true, action_hash: @hash, action_size: 10, cas_endpoint: "grpcs://cache.example"} = operation

    assert_received {:node, "create", %{template_tag: @image, expires_at_unix: expires}}
    assert expires > DateTime.to_unix(DateTime.utc_now())
    assert_received {:node, "exec", %{cmd: ["/usr/local/bin/sbx-executor"], env: env}}
    assert env["SBX_EXECUTION_TOKEN"] == "scoped-credential"

    assert %{"hash" => @hash, "image" => @image, "instance" => instance} = JSON.decode!(env["SBX_EXECUTION_REQUEST"])
    assert instance == project.name

    assert_receive {:node, "delete", %{sandbox_id: _}}
    eventually(fn -> vm_rows(project) == [] end)
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

  test "a warm VM is kept ready and taken by the next action", %{project: project} do
    {:ok, _} = configure(project, warm_pool_size: 1)
    stub_node()
    assert {:ok, %{done: true}} = submit(project)

    eventually(fn ->
      match?([%Sandbox{state: :running}], vm_rows(project))
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

  test "invalid requests are rejected before scheduling", %{project: project} do
    assert {:error, :invalid_request} = submit(project, %{"hash" => "short"})
    assert {:error, :invalid_request} = submit(project, %{"size" => -1})
    assert {:error, :invalid_request} = submit(project, %{"skip_cache" => "yes"})
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

  defp flush_node_messages do
    receive do
      {:node, _, _} -> flush_node_messages()
    after
      0 -> :ok
    end
  end
end
