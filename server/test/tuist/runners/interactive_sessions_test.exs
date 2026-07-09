defmodule Tuist.Runners.InteractiveSessionsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Repo
  alias Tuist.Runners.InteractiveSession
  alias Tuist.Runners.InteractiveSessionConnection
  alias Tuist.Runners.InteractiveSessions
  alias Tuist.Runners.Workers.CloseDisconnectedInteractiveSessionWorker

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

      assert {:ok, validated} = InteractiveSessions.validate_token(session.token, account, user)
      assert validated.id == session.id
    end

    test "rejects a token for the wrong account or user" do
      account = account_fixture()
      user = user_fixture()
      other_account = account_fixture()
      other_user = user_fixture()
      {:ok, session} = InteractiveSessions.request_vnc(job(account), account, user)

      assert {:error, :invalid_or_expired} = InteractiveSessions.validate_token(session.token, other_account, user)
      assert {:error, :invalid_or_expired} = InteractiveSessions.validate_token(session.token, account, other_user)
    end

    test "returns the existing open session with a rotated token for duplicate requests" do
      account = account_fixture()
      user = user_fixture()
      job = job(account, %{workflow_job_id: 70_001, pod_name: "pod-one"})

      assert {:ok, first} = InteractiveSessions.request_vnc(job, account, user)
      assert {:ok, second} = InteractiveSessions.request_vnc(job, account, user)

      assert second.id == first.id
      assert is_binary(second.token)
      assert second.token != first.token
      assert {:error, :invalid_or_expired} = InteractiveSessions.validate_token(first.token, account, user)
      assert {:ok, validated} = InteractiveSessions.validate_token(second.token, account, user)
      assert validated.id == first.id
    end

    test "moves token ownership to the latest requester when refreshing an open session" do
      account = account_fixture()
      first_user = user_fixture()
      second_user = user_fixture()
      job = job(account, %{workflow_job_id: 70_003, pod_name: "pod-two-users"})

      assert {:ok, first} = InteractiveSessions.request_vnc(job, account, first_user)
      assert {:ok, second} = InteractiveSessions.request_vnc(job, account, second_user)

      assert second.id == first.id
      assert second.requested_by_user_id == second_user.id
      assert {:error, :invalid_or_expired} = InteractiveSessions.validate_token(second.token, account, first_user)
      assert {:ok, validated} = InteractiveSessions.validate_token(second.token, account, second_user)
      assert validated.id == second.id
    end

    test "keeps active connection rows when refreshing an open session token" do
      account = account_fixture()
      user = user_fixture()
      job = job(account, %{workflow_job_id: 70_002, pod_name: "pod-token-refresh"})

      {:ok, session} = InteractiveSessions.request_vnc(job, account, user)
      {:ok, active} = InteractiveSessions.mark_active(session, "connection-before-refresh")

      assert {:ok, refreshed} = InteractiveSessions.request_vnc(job, account, user)

      assert refreshed.id == active.id

      assert Repo.get_by!(InteractiveSessionConnection,
               interactive_session_id: active.id,
               connection_id: "connection-before-refresh"
             ).disconnected_at == nil
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

  describe "request_vnc_relay/1" do
    test "patches the runner pod with the server-owned VNC request annotation" do
      account = account_fixture()
      user = user_fixture()
      {:ok, session} = InteractiveSessions.request_vnc(job(account, %{pod_name: "pod-request"}), account, user)

      expect(K8sClient, :patch_pod, fn "tuist-runners", "pod-request", patch ->
        annotations = get_in(patch, ["metadata", "annotations"])

        assert annotations[InteractiveSessions.vnc_session_id_annotation()] == Integer.to_string(session.id)
        assert is_binary(annotations[InteractiveSessions.vnc_requested_at_annotation()])
        assert is_binary(annotations[InteractiveSessions.vnc_relay_token_hash_annotation()])

        {:ok, %{}}
      end)

      assert :ok = InteractiveSessions.request_vnc_relay(session)
    end

    test "closes the session when the runner pod no longer exists" do
      account = account_fixture()
      user = user_fixture()
      {:ok, session} = InteractiveSessions.request_vnc(job(account, %{pod_name: "pod-missing"}), account, user)

      expect(K8sClient, :patch_pod, fn "tuist-runners", "pod-missing", _patch ->
        {:error, :not_found}
      end)

      assert {:error, :pod_unavailable} = InteractiveSessions.request_vnc_relay(session)

      closed = Repo.reload!(session)
      assert closed.state == :closed
      assert closed.close_reason == "pod_not_found"
      assert closed.closed_at
      assert InteractiveSessions.current_for_job(account.id, session.workflow_job_id, :vnc) == nil
    end
  end

  describe "sync_vnc_relay_state/1" do
    test "marks a requested session ready from matching pod relay annotations" do
      account = account_fixture()
      user = user_fixture()
      {:ok, session} = InteractiveSessions.request_vnc(job(account, %{pod_name: "pod-ready"}), account, user)

      expect(K8sClient, :get_pod, fn "tuist-runners", "pod-ready" ->
        {:ok,
         %{
           "metadata" => %{
             "annotations" => %{
               InteractiveSessions.vnc_session_id_annotation() => Integer.to_string(session.id),
               InteractiveSessions.vnc_state_annotation() => "ready",
               InteractiveSessions.vnc_relay_host_annotation() => "100.88.125.7",
               InteractiveSessions.vnc_relay_port_annotation() => "49152"
             }
           }
         }}
      end)

      assert {:ok, ready} = InteractiveSessions.sync_vnc_relay_state(session)
      assert ready.state == :ready
      assert ready.relay_host == "100.88.125.7"
      assert ready.relay_port == 49_152
      assert ready.relay_ready_at
    end

    test "ignores stale relay annotations for a different session" do
      account = account_fixture()
      user = user_fixture()
      {:ok, session} = InteractiveSessions.request_vnc(job(account, %{pod_name: "pod-stale"}), account, user)

      expect(K8sClient, :get_pod, fn "tuist-runners", "pod-stale" ->
        {:ok,
         %{
           "metadata" => %{
             "annotations" => %{
               InteractiveSessions.vnc_session_id_annotation() => "9999",
               InteractiveSessions.vnc_state_annotation() => "ready",
               InteractiveSessions.vnc_relay_host_annotation() => "100.88.125.7",
               InteractiveSessions.vnc_relay_port_annotation() => "49152"
             }
           }
         }}
      end)

      assert {:ok, unchanged} = InteractiveSessions.sync_vnc_relay_state(session)
      assert unchanged.state == :requested
      assert unchanged.relay_host == nil
      assert unchanged.relay_port == nil
    end

    test "closes the session when the runner pod disappears" do
      account = account_fixture()
      user = user_fixture()
      {:ok, session} = InteractiveSessions.request_vnc(job(account, %{pod_name: "pod-gone"}), account, user)

      expect(K8sClient, :get_pod, fn "tuist-runners", "pod-gone" ->
        {:error, :not_found}
      end)

      assert {:ok, closed} = InteractiveSessions.sync_vnc_relay_state(session)
      assert closed.state == :closed
      assert closed.close_reason == "pod_not_found"
      assert closed.closed_at
      assert InteractiveSessions.current_for_job(account.id, session.workflow_job_id, :vnc) == nil
    end
  end

  describe "mark_vnc_relay_ready/3" do
    test "marks a requested VNC session ready without touching Kubernetes" do
      account = account_fixture()
      user = user_fixture()
      {:ok, session} = InteractiveSessions.request_vnc(job(account), account, user)

      assert {:ok, ready} = InteractiveSessions.mark_vnc_relay_ready(session, "127.0.0.1", 5900)
      assert ready.state == :ready
      assert ready.relay_host == "127.0.0.1"
      assert ready.relay_port == 5900
      assert ready.relay_ready_at
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

  describe "mark_active/2" do
    test "records a connection row for the active browser WebSocket" do
      account = account_fixture()
      user = user_fixture()
      {:ok, session} = InteractiveSessions.request_vnc(job(account), account, user)

      assert {:ok, active} = InteractiveSessions.mark_active(session, "connection-one")

      assert active.state == :active
      assert active.connected_at
      assert active.last_activity_at

      connection =
        Repo.get_by!(InteractiveSessionConnection,
          interactive_session_id: active.id,
          connection_id: "connection-one"
        )

      assert connection.connected_at
      assert connection.disconnected_at == nil
    end
  end

  describe "schedule_disconnect_close/2" do
    test "enqueues delayed cleanup for the active connection" do
      account = account_fixture()
      user = user_fixture()
      {:ok, session} = InteractiveSessions.request_vnc(job(account), account, user)
      {:ok, active} = InteractiveSessions.mark_active(session, "connection-scheduled")

      assert {:ok, _job} =
               InteractiveSessions.schedule_disconnect_close(active, "connection-scheduled", grace_seconds: 15)

      connection =
        Repo.get_by!(InteractiveSessionConnection,
          interactive_session_id: active.id,
          connection_id: "connection-scheduled"
        )

      assert connection.disconnected_at

      assert_enqueued(
        worker: CloseDisconnectedInteractiveSessionWorker,
        args: %{session_id: active.id, connection_id: "connection-scheduled"}
      )
    end
  end

  describe "close_if_disconnected/2" do
    test "closes the still-disconnected session and clears the VNC relay request" do
      account = account_fixture()
      user = user_fixture()
      pod_name = "pod-disconnected"
      {:ok, session} = InteractiveSessions.request_vnc(job(account, %{pod_name: pod_name}), account, user)
      {:ok, active} = InteractiveSessions.mark_active(session, "connection-disconnected")

      assert {:ok, _job} =
               InteractiveSessions.schedule_disconnect_close(active, "connection-disconnected", grace_seconds: 15)

      expect(K8sClient, :get_pod, fn "tuist-runners", ^pod_name ->
        {:ok,
         %{
           "metadata" => %{
             "annotations" => %{
               InteractiveSessions.vnc_session_id_annotation() => Integer.to_string(active.id),
               InteractiveSessions.vnc_requested_at_annotation() => "2026-07-08T10:00:00Z",
               InteractiveSessions.vnc_relay_token_hash_annotation() => "relay-token-hash",
               InteractiveSessions.vnc_state_annotation() => "ready",
               InteractiveSessions.vnc_relay_host_annotation() => "100.88.125.7",
               InteractiveSessions.vnc_relay_port_annotation() => "49152",
               InteractiveSessions.vnc_relay_ready_at_annotation() => "2026-07-08T10:00:02Z"
             }
           }
         }}
      end)

      expect(K8sClient, :patch_pod, fn "tuist-runners", ^pod_name, patch ->
        annotations = get_in(patch, ["metadata", "annotations"])

        assert annotations[InteractiveSessions.vnc_session_id_annotation()] == nil
        assert annotations[InteractiveSessions.vnc_requested_at_annotation()] == nil
        assert annotations[InteractiveSessions.vnc_relay_token_hash_annotation()] == nil
        assert annotations[InteractiveSessions.vnc_state_annotation()] == nil
        assert annotations[InteractiveSessions.vnc_relay_host_annotation()] == nil
        assert annotations[InteractiveSessions.vnc_relay_port_annotation()] == nil
        assert annotations[InteractiveSessions.vnc_relay_ready_at_annotation()] == nil

        {:ok, %{}}
      end)

      assert {:ok, closed} = InteractiveSessions.close_if_disconnected(active.id, "connection-disconnected")

      assert closed.state == :closed
      assert closed.close_reason == "browser_disconnect"
      assert closed.closed_at
    end

    test "keeps the session open while another WebSocket connection is active" do
      account = account_fixture()
      user = user_fixture()
      {:ok, session} = InteractiveSessions.request_vnc(job(account), account, user)
      {:ok, active} = InteractiveSessions.mark_active(session, "connection-old")
      {:ok, reconnected} = InteractiveSessions.mark_active(active, "connection-new")

      assert {:ok, _job} = InteractiveSessions.schedule_disconnect_close(reconnected, "connection-old", grace_seconds: 15)
      assert {:ok, :active_connections} = InteractiveSessions.close_if_disconnected(reconnected.id, "connection-old")

      assert Repo.reload!(session).closed_at == nil

      assert Repo.get_by!(InteractiveSessionConnection,
               interactive_session_id: reconnected.id,
               connection_id: "connection-old"
             ).disconnected_at

      assert Repo.get_by!(InteractiveSessionConnection,
               interactive_session_id: reconnected.id,
               connection_id: "connection-new"
             ).disconnected_at == nil
    end

    test "waits for the newest disconnected browser cleanup before closing a shared session" do
      account = account_fixture()
      user = user_fixture()
      pod_name = "pod-shared-disconnect"
      {:ok, session} = InteractiveSessions.request_vnc(job(account, %{pod_name: pod_name}), account, user)
      {:ok, active} = InteractiveSessions.mark_active(session, "connection-old")
      {:ok, shared} = InteractiveSessions.mark_active(active, "connection-new")

      assert {:ok, _job} = InteractiveSessions.schedule_disconnect_close(shared, "connection-old", grace_seconds: 15)
      assert {:ok, _job} = InteractiveSessions.schedule_disconnect_close(shared, "connection-new", grace_seconds: 15)

      assert {:ok, :newer_disconnect_pending} =
               InteractiveSessions.close_if_disconnected(shared.id, "connection-old")

      assert Repo.reload!(session).closed_at == nil

      expect(K8sClient, :get_pod, fn "tuist-runners", ^pod_name ->
        {:error, :not_found}
      end)

      assert {:ok, closed} = InteractiveSessions.close_if_disconnected(shared.id, "connection-new")

      assert closed.state == :closed
      assert closed.close_reason == "browser_disconnect"
      assert closed.closed_at
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

      expect(K8sClient, :get_pod, fn "tuist-runners", _pod_name ->
        {:error, :not_found}
      end)

      assert {:ok, 1} = InteractiveSessions.close_expired(~U[2026-07-06 12:00:00Z])

      expired = Repo.reload!(session)
      assert expired.state == :closed
      assert expired.close_reason == "expired"
      assert DateTime.compare(expired.closed_at, ~U[2026-07-06 12:00:00Z]) == :eq
    end
  end
end
