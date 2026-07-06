defmodule Tuist.Runners.InteractiveSessionsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.InteractiveSession
  alias Tuist.Runners.InteractiveSessions

  defp job(account, attrs \\ %{}) do
    Map.merge(
      %{
        account_id: account.id,
        workflow_job_id: System.unique_integer([:positive]),
        fleet_name: "macos-xcode-26-5",
        status: "running",
        pod_name: "tuist-macos-runner-#{System.unique_integer([:positive])}"
      },
      attrs
    )
  end

  describe "request_vnc/3" do
    test "creates a requested VNC session with a virtual token and persisted hash" do
      account = account_fixture()
      user = user_fixture()

      assert {:ok, %InteractiveSession{} = session} = InteractiveSessions.request_vnc(job(account), account, user)

      assert session.kind == :vnc
      assert session.state == :requested
      assert session.account_id == account.id
      assert session.requested_by_user_id == user.id
      assert is_binary(session.token)
      assert byte_size(session.token_hash) == 32
      assert DateTime.after?(session.expires_at, DateTime.utc_now())

      persisted = Repo.get!(InteractiveSession, session.id)
      assert persisted.token_hash == session.token_hash
      assert persisted.token == nil
    end

    test "validates the freshly minted token against the stored hash" do
      account = account_fixture()
      user = user_fixture()
      {:ok, session} = InteractiveSessions.request_vnc(job(account), account, user)

      assert {:ok, validated} = InteractiveSessions.validate_token(session.token)
      assert validated.id == session.id
    end

    test "returns the existing open session for duplicate requests" do
      account = account_fixture()
      user = user_fixture()
      job = job(account, %{workflow_job_id: 70_001, pod_name: "pod-one"})

      assert {:ok, first} = InteractiveSessions.request_vnc(job, account, user)
      assert {:ok, second} = InteractiveSessions.request_vnc(job, account, user)

      assert second.id == first.id
      assert second.token == nil
    end

    test "rejects non-macOS jobs" do
      account = account_fixture()
      user = user_fixture()

      assert {:error, :unsupported_platform} =
               InteractiveSessions.request_vnc(job(account, %{fleet_name: "linux-amd64"}), account, user)
    end

    test "rejects jobs that are not running or claimed" do
      account = account_fixture()
      user = user_fixture()

      assert {:error, :job_not_running} =
               InteractiveSessions.request_vnc(job(account, %{status: "completed"}), account, user)
    end
  end

  describe "close_by_pod_name/3" do
    test "closes open sessions for the stopped pod" do
      account = account_fixture()
      user = user_fixture()
      pod_name = "tuist-macos-runner-stopped"
      {:ok, session} = InteractiveSessions.request_vnc(job(account, %{pod_name: pod_name}), account, user)

      assert {:ok, closed} = InteractiveSessions.close_by_pod_name(pod_name, ~U[2026-07-06 12:00:00Z])

      assert closed.id == session.id
      assert closed.state == :closed
      assert closed.close_reason == "pod_exit"
      assert DateTime.compare(closed.closed_at, ~U[2026-07-06 12:00:00Z]) == :eq
      assert InteractiveSessions.current_for_job(account.id, session.workflow_job_id, :vnc) == nil
    end
  end

  describe "close_expired/1" do
    test "closes open sessions whose hard TTL elapsed" do
      account = account_fixture()
      user = user_fixture()
      {:ok, session} = InteractiveSessions.request_vnc(job(account), account, user)

      session
      |> Ecto.Changeset.change(expires_at: ~U[2026-07-06 11:59:59Z])
      |> Repo.update!()

      assert {:ok, 1} = InteractiveSessions.close_expired(~U[2026-07-06 12:00:00Z])

      expired = Repo.reload!(session)
      assert expired.state == :closed
      assert expired.close_reason == "expired"
      assert DateTime.compare(expired.closed_at, ~U[2026-07-06 12:00:00Z]) == :eq
    end
  end
end
