defmodule Tuist.OrchardTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Orchard

  describe "service accounts" do
    test "create_service_account/1 hashes the token and round-trips authentication" do
      assert {:ok, account} =
               Orchard.create_service_account(%{
                 "name" => "vk-orchard",
                 "token" => "supersecret",
                 "roles" => ["compute:read", "compute:write"]
               })

      assert account.name == "vk-orchard"
      # The plaintext token is never persisted on the struct.
      refute is_binary(account.token_hash) and account.token_hash == "supersecret"

      assert {:ok, %{id: id}} =
               Orchard.authenticate_service_account("vk-orchard", "supersecret")

      assert id == account.id
      assert :error = Orchard.authenticate_service_account("vk-orchard", "wrong")
      assert :error = Orchard.authenticate_service_account("nonexistent", "supersecret")
    end

    test "has_role?/2 checks role membership" do
      {:ok, account} =
        Orchard.create_service_account(%{
          "name" => "vk-orchard-roles",
          "token" => "tok",
          "roles" => ["compute:read"]
        })

      assert Orchard.has_role?(account, "compute:read")
      refute Orchard.has_role?(account, "compute:write")
    end

    test "create_service_account/1 rejects unknown roles" do
      assert {:error, changeset} =
               Orchard.create_service_account(%{
                 "name" => "bad-roles",
                 "token" => "tok",
                 "roles" => ["root"]
               })

      assert "has an invalid entry" in errors_on(changeset).roles
    end
  end

  describe "workers" do
    test "register_worker/1 inserts a new worker on first call" do
      assert {:ok, worker} =
               Orchard.register_worker(%{
                 "name" => "mac-mini-1",
                 "machine_id" => "abc123",
                 "default_cpu" => 8,
                 "default_memory" => 16_384
               })

      assert worker.name == "mac-mini-1"
      assert worker.machine_id == "abc123"
      assert worker.last_seen_at != nil
    end

    test "register_worker/1 rejects re-registration with a different machine_id" do
      {:ok, _} =
        Orchard.register_worker(%{
          "name" => "mac-mini-conflict",
          "machine_id" => "first-machine"
        })

      assert {:error, :machine_id_conflict} =
               Orchard.register_worker(%{
                 "name" => "mac-mini-conflict",
                 "machine_id" => "different-machine"
               })
    end

    test "register_worker/1 updates capacity when same machine_id re-registers" do
      {:ok, _} =
        Orchard.register_worker(%{
          "name" => "mac-mini-update",
          "machine_id" => "stable",
          "default_cpu" => 4
        })

      assert {:ok, updated} =
               Orchard.register_worker(%{
                 "name" => "mac-mini-update",
                 "machine_id" => "stable",
                 "default_cpu" => 8
               })

      assert updated.default_cpu == 8
    end
  end

  describe "VMs" do
    test "create_vm/1 stores a new VM in pending status with a uid" do
      assert {:ok, vm} =
               Orchard.create_vm(%{
                 "name" => "xcresult-processor-prod-0",
                 "image" => "ghcr.io/tuist/tuist-xcresult-processor:abc"
               })

      assert vm.status == "pending"
      assert vm.worker_name == nil
      assert is_binary(vm.uid)
      assert vm.image_pull_policy == "if-not-present"
    end

    test "create_vm/1 rejects invalid name" do
      assert {:error, changeset} =
               Orchard.create_vm(%{"name" => "Invalid Name", "image" => "img"})

      assert "has invalid format" in errors_on(changeset).name
    end

    test "schedule_vm/4 assigns a worker and bumps assigned resources" do
      {:ok, worker} =
        Orchard.register_worker(%{
          "name" => "mac-mini-sched",
          "machine_id" => "m1",
          "default_cpu" => 4
        })

      {:ok, vm} =
        Orchard.create_vm(%{
          "name" => "vm-sched",
          "image" => "ghcr.io/tuist/img:1"
        })

      {:ok, scheduled} = Orchard.schedule_vm(vm, worker, 4, 8192)

      assert scheduled.worker_name == "mac-mini-sched"
      assert scheduled.assigned_cpu == 4
      assert scheduled.assigned_memory == 8192
    end

    test "delete_vm/1 removes the row" do
      {:ok, vm} =
        Orchard.create_vm(%{"name" => "vm-del", "image" => "img"})

      assert {:ok, _} = Orchard.delete_vm(vm)
      assert Orchard.get_vm_by_name("vm-del") == nil
    end
  end

  describe "VM events" do
    test "append_vm_events/2 assigns monotonic sequences and list_vm_events/2 honors `since`" do
      {:ok, _vm} = Orchard.create_vm(%{"name" => "vm-events", "image" => "img"})

      assert {:ok, _} =
               Orchard.append_vm_events("vm-events", [
                 %{"kind" => "log", "payload" => %{"line" => "first"}},
                 %{"kind" => "log", "payload" => %{"line" => "second"}}
               ])

      events = Orchard.list_vm_events("vm-events", since: 0)
      assert length(events) == 2
      assert Enum.map(events, & &1.sequence) == [1, 2]

      tail = Orchard.list_vm_events("vm-events", since: 1)
      assert length(tail) == 1
      assert hd(tail).sequence == 2
    end
  end
end
