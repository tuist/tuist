defmodule Tuist.IdempotentRequestsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.IdempotentRequests
  alias Tuist.IdempotentRequests.Claim
  alias Tuist.Repo

  defp counting_create(result) do
    test_pid = self()

    fn ->
      send(test_pid, :created)
      result
    end
  end

  defp insert_claim(attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert!(
      struct(
        Claim,
        Map.merge(
          %{
            kind: "test_run",
            lease_id: Ecto.UUID.generate(),
            claimed_at: now,
            inserted_at: now,
            updated_at: now
          },
          attrs
        )
      )
    )
  end

  test "runs the creation once per id and replays its result" do
    request_id = UUIDv7.generate()

    assert {:ok, %{id: 1}} = IdempotentRequests.run("test_run", 1, request_id, counting_create({:ok, %{id: 1}}))
    assert {:replayed, %{id: 1}} = IdempotentRequests.run("test_run", 1, request_id, counting_create({:ok, %{id: 2}}))

    assert_received :created
    refute_received :created
  end

  test "scopes ids by project and kind" do
    request_id = UUIDv7.generate()

    assert {:ok, :a} = IdempotentRequests.run("test_run", 1, request_id, fn -> {:ok, :a} end)
    assert {:ok, :b} = IdempotentRequests.run("test_run", 2, request_id, fn -> {:ok, :b} end)
    assert {:ok, :c} = IdempotentRequests.run("gradle_build", 1, request_id, fn -> {:ok, :c} end)
  end

  test "runs the creation every time without an id or with an id that isn't a UUID" do
    assert {:ok, 1} = IdempotentRequests.run("test_run", 1, nil, fn -> {:ok, 1} end)
    assert {:ok, 2} = IdempotentRequests.run("test_run", 1, nil, fn -> {:ok, 2} end)
    assert {:ok, 3} = IdempotentRequests.run("command_event", 1, "not-a-uuid", fn -> {:ok, 3} end)
    assert {:ok, 4} = IdempotentRequests.run("command_event", 1, "not-a-uuid", fn -> {:ok, 4} end)
    assert Repo.aggregate(Claim, :count) == 0
  end

  test "releases the claim when the creation fails, so a retry creates" do
    request_id = UUIDv7.generate()

    assert {:error, :unavailable} =
             IdempotentRequests.run("test_run", 1, request_id, fn -> {:error, :unavailable} end)

    assert {:ok, :created} = IdempotentRequests.run("test_run", 1, request_id, fn -> {:ok, :created} end)
  end

  test "releases the claim when the creation raises" do
    request_id = UUIDv7.generate()

    assert_raise RuntimeError, fn ->
      IdempotentRequests.run("test_run", 1, request_id, fn -> raise "boom" end)
    end

    assert {:ok, :created} = IdempotentRequests.run("test_run", 1, request_id, fn -> {:ok, :created} end)
  end

  test "reports a claim still being processed once the wait runs out" do
    request_id = UUIDv7.generate()
    insert_claim(%{project_id: 1, request_id: request_id})

    assert {:error, :in_progress} =
             IdempotentRequests.run("test_run", 1, request_id, counting_create({:ok, :duplicate}), wait_timeout: 0)

    refute_received :created
  end

  test "waits for a claim being processed and replays its result" do
    request_id = UUIDv7.generate()
    test_pid = self()

    first =
      Task.async(fn ->
        IdempotentRequests.run("test_run", 1, request_id, fn ->
          send(test_pid, {:claimed, self()})

          receive do
            :finish -> {:ok, :first}
          end
        end)
      end)

    assert_receive {:claimed, creator}
    duplicate = counting_create({:ok, :second})
    second = Task.async(fn -> IdempotentRequests.run("test_run", 1, request_id, duplicate) end)
    send(creator, :finish)

    assert Task.await(first) == {:ok, :first}
    assert Task.await(second) == {:replayed, :first}
    refute_received :created
  end

  test "takes over a claim whose lease expired" do
    request_id = UUIDv7.generate()
    claimed_at = DateTime.utc_now() |> DateTime.add(-11, :minute) |> DateTime.truncate(:second)
    insert_claim(%{project_id: 1, request_id: request_id, claimed_at: claimed_at})

    assert {:ok, :created} = IdempotentRequests.run("test_run", 1, request_id, fn -> {:ok, :created} end)
    assert {:replayed, :created} = IdempotentRequests.run("test_run", 1, request_id, fn -> {:ok, :again} end)
  end

  test "an expired lease holder can't complete or release the claim that replaced it" do
    request_id = UUIDv7.generate()
    claimed_at = DateTime.utc_now() |> DateTime.add(-11, :minute) |> DateTime.truncate(:second)
    %Claim{lease_id: expired_lease_id} = insert_claim(%{project_id: 1, request_id: request_id, claimed_at: claimed_at})

    assert {:ok, :new} = IdempotentRequests.run("test_run", 1, request_id, fn -> {:ok, :new} end)

    claim = Repo.get_by!(Claim, project_id: 1, kind: "test_run", request_id: request_id)
    refute claim.lease_id == expired_lease_id
    assert {:replayed, :new} = IdempotentRequests.run("test_run", 1, request_id, fn -> {:ok, :again} end)
  end

  test "update_result replaces the recorded result of a completed request" do
    request_id = UUIDv7.generate()

    assert {:ok, %{scheduled: false}} =
             IdempotentRequests.run("test_run", 1, request_id, fn -> {:ok, %{scheduled: false}} end)

    assert :ok = IdempotentRequests.update_result("test_run", 1, request_id, %{scheduled: true})
    assert {:replayed, %{scheduled: true}} = IdempotentRequests.run("test_run", 1, request_id, fn -> {:ok, :again} end)
  end

  test "prune deletes claims older than an hour" do
    old_id = UUIDv7.generate()
    recent_id = UUIDv7.generate()

    insert_claim(%{
      project_id: 1,
      request_id: old_id,
      claimed_at: DateTime.utc_now() |> DateTime.add(-61, :minute) |> DateTime.truncate(:second)
    })

    insert_claim(%{project_id: 1, request_id: recent_id})

    assert IdempotentRequests.prune() == 1
    assert [%Claim{request_id: ^recent_id}] = Repo.all(Claim)
  end
end
