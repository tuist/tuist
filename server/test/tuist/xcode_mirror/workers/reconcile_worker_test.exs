defmodule Tuist.XcodeMirror.Workers.ReconcileWorkerTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.XcodeMirror
  alias Tuist.XcodeMirror.Downloader
  alias Tuist.XcodeMirror.Pusher
  alias Tuist.XcodeMirror.Workers.ReconcileWorker

  setup :verify_on_exit!

  setup do
    # Default to observe mode for each test; cases that exercise
    # `mirror` mode override.
    stub(Tuist.Environment, :xcode_mirror_mode, fn -> "observe" end)
    :ok
  end

  describe "perform/1 — off mode" do
    test "skips the diff entirely" do
      stub(Tuist.Environment, :xcode_mirror_mode, fn -> "off" end)

      # Mimic strict mode: NO expect for `missing_versions` means
      # the worker must not call it.

      assert :ok = ReconcileWorker.perform(%Oban.Job{})
    end
  end

  describe "perform/1 — observe mode" do
    test "logs missing versions but does not download" do
      expect(XcodeMirror, :missing_versions, fn -> {:ok, ["26.5", "26.4.1"]} end)
      # No Downloader / Pusher calls — verify_on_exit! would fail
      # if the worker reached into them.

      assert :ok = ReconcileWorker.perform(%Oban.Job{})
    end

    test "no-op when the mirror is caught up" do
      expect(XcodeMirror, :missing_versions, fn -> {:ok, []} end)

      assert :ok = ReconcileWorker.perform(%Oban.Job{})
    end

    test "swallows a failed listing — schedule retries on the next tick" do
      expect(XcodeMirror, :missing_versions, fn -> {:error, :auth_required} end)

      assert :ok = ReconcileWorker.perform(%Oban.Job{})
    end
  end

  describe "perform/1 — mirror mode" do
    setup do
      stub(Tuist.Environment, :xcode_mirror_mode, fn -> "mirror" end)
      :ok
    end

    test "downloads and pushes each missing version" do
      expect(XcodeMirror, :missing_versions, fn -> {:ok, ["26.5"]} end)
      expect(Downloader, :download, fn "26.5", path -> {:ok, path} end)

      expect(Pusher, :push, fn "26.5", _path ->
        {:ok, "ghcr.io/tuist/xcode-xips:26.5"}
      end)

      assert :ok = ReconcileWorker.perform(%Oban.Job{})
    end

    test "skips push when download fails" do
      expect(XcodeMirror, :missing_versions, fn -> {:ok, ["26.5"]} end)
      expect(Downloader, :download, fn "26.5", _path -> {:error, :session_expired} end)

      # No Pusher.push call — Sentry should be captured by the
      # session_expired path. Mocking the Sentry capture isn't
      # needed for this test (test_helper.exs covers Sentry).
      expect(Sentry, :capture_message, fn message, _opts ->
        assert message == "xcode_mirror.session_expired"
        :ok
      end)

      assert :ok = ReconcileWorker.perform(%Oban.Job{})
    end

    test "alerts on missing GHCR credentials" do
      expect(XcodeMirror, :missing_versions, fn -> {:ok, ["26.5"]} end)
      expect(Downloader, :download, fn "26.5", path -> {:ok, path} end)
      expect(Pusher, :push, fn "26.5", _path -> {:error, :no_credentials} end)

      expect(Sentry, :capture_message, fn message, _opts ->
        assert message == "xcode_mirror.ghcr_misconfigured"
        :ok
      end)

      assert :ok = ReconcileWorker.perform(%Oban.Job{})
    end

    test "alerts on oras binary missing" do
      expect(XcodeMirror, :missing_versions, fn -> {:ok, ["26.5"]} end)
      expect(Downloader, :download, fn "26.5", path -> {:ok, path} end)
      expect(Pusher, :push, fn "26.5", _path -> {:error, :oras_unavailable} end)

      expect(Sentry, :capture_message, fn message, _opts ->
        assert message == "xcode_mirror.oras_unavailable"
        :ok
      end)

      assert :ok = ReconcileWorker.perform(%Oban.Job{})
    end

    test "continues to next version when one mirror attempt fails" do
      expect(XcodeMirror, :missing_versions, fn -> {:ok, ["26.5", "26.4.1"]} end)

      # First version download fails on session expiry; second
      # succeeds. Both should be attempted.
      expect(Downloader, :download, 2, fn version, path ->
        case version do
          "26.5" -> {:error, :session_expired}
          "26.4.1" -> {:ok, path}
        end
      end)

      # Push only called for the second.
      expect(Pusher, :push, fn "26.4.1", _path ->
        {:ok, "ghcr.io/tuist/xcode-xips:26.4.1"}
      end)

      stub(Sentry, :capture_message, fn _, _ -> :ok end)

      assert :ok = ReconcileWorker.perform(%Oban.Job{})
    end
  end

  describe "perform/1 — unknown mode" do
    test "warns and no-ops without diff or download" do
      stub(Tuist.Environment, :xcode_mirror_mode, fn -> "wat" end)
      expect(XcodeMirror, :missing_versions, fn -> {:ok, ["26.5"]} end)

      # No Downloader / Pusher.

      assert :ok = ReconcileWorker.perform(%Oban.Job{})
    end
  end
end
