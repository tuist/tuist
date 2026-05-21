defmodule Tuist.XcodeMirror.Workers.ReconcileWorker do
  @moduledoc """
  Periodic reconcile loop for the Xcode .xip mirror.

  On each tick:

    1. Fetch the list of released Xcodes from `xcodereleases.com`
       (no auth required for the *listing*).
    2. List the tags currently in `ghcr.io/tuist/xcode-xips`.
    3. Diff — anything Apple has released that we haven't mirrored
       yet is a candidate.
    4. For each missing version:
       a. Download from Apple's CDN to a temp file using the
          session cookies from the secret.
       b. Push to GHCR via the `oras` CLI.
       c. Delete the temp file (it's ~10 GB per).

  ## Behaviour by mirror mode

  The `TUIST_XCODE_MIRROR_MODE` env var selects between three
  modes (read in `Tuist.Environment.xcode_mirror_mode/1`):

    * `"off"` — skip every step. Useful during incident response
      or when an Apple API change has us off the rails.
    * `"observe"` — Phase 2 default. Compute the diff, log /
      metric-emit it, but don't download. Lets us validate Apple
      + GHCR connectivity (and Apple session-cookie expiry
      alerting) before trusting the worker with multi-GB
      transfers.
    * `"mirror"` — Phase 3 default. Full download + push loop.

  The mode is read on every tick so flipping it doesn't require
  a deploy.

  ## Failure handling

  Each tick is bounded; the worker uses `max_attempts: 1` and
  relies on the cron schedule for retries. Per-version failures
  don't abort the tick — we log, optionally Sentry-capture, and
  move on to the next missing version. The next tick will see the
  same diff and try again.

  ## Cost / cadence

  6 hours between ticks. Apple ships a new Xcode at most a few
  times a year; the steady-state cost per tick is one
  xcodereleases.com GET + one GHCR `tags/list`, both sub-second.
  A new Xcode adds one ~10 GB transfer once.

  Concurrency: `unique` on a long window so two ticks can never
  overlap (which would let two workers fight over the same .xip
  download). The unique window is generous in case a download
  takes its time.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: 3600]

  alias Tuist.XcodeMirror
  alias Tuist.XcodeMirror.Downloader
  alias Tuist.XcodeMirror.Pusher

  require Logger

  @tmp_root "/tmp/xcode-mirror"

  @impl Oban.Worker
  def perform(_job) do
    mode = mirror_mode()

    Logger.info("xcode_mirror: reconcile tick start", mode: mode)

    case mode do
      "off" ->
        :ok

      _ ->
        case XcodeMirror.missing_versions() do
          {:ok, missing} ->
            handle_missing(missing, mode)
            :ok

          {:error, reason} ->
            Logger.warning("xcode_mirror: reconcile failed to compute diff",
              reason: inspect(reason)
            )

            # Don't fail the Oban job — let the schedule retry on
            # the next tick. A failed listing is recoverable, no
            # operator action needed.
            :ok
        end
    end
  end

  defp handle_missing([], _mode) do
    Logger.info("xcode_mirror: mirror is up to date")
    :ok
  end

  defp handle_missing(missing, "observe") do
    Logger.warning("xcode_mirror: missing versions (observe mode, not downloading)",
      count: length(missing),
      versions: Enum.join(missing, ", ")
    )

    :ok
  end

  defp handle_missing(missing, "mirror") do
    Logger.info("xcode_mirror: mirror catching up",
      count: length(missing),
      versions: Enum.join(missing, ", ")
    )

    File.mkdir_p!(@tmp_root)

    Enum.each(missing, &mirror_one/1)
  end

  defp handle_missing(_missing, other) do
    Logger.warning("xcode_mirror: unrecognised TUIST_XCODE_MIRROR_MODE",
      mode: other,
      action: "defaulting to observe"
    )

    :ok
  end

  defp mirror_one(version) do
    xip_path = Path.join(@tmp_root, "Xcode-#{version}.xip")

    Logger.info("xcode_mirror: mirroring Xcode #{version}", version: version)

    try do
      with {:ok, _} <- Downloader.download(version, xip_path),
           {:ok, tag} <- Pusher.push(version, xip_path) do
        Logger.info("xcode_mirror: mirrored Xcode #{version}", version: version, tag: tag)
      else
        {:error, :no_session} -> capture_session_expired(version, :no_session)
        {:error, :session_expired} -> capture_session_expired(version, :session_expired)
        {:error, :no_credentials} -> capture_ghcr_misconfigured(version)
        {:error, :oras_unavailable} -> capture_oras_missing(version)
        {:error, reason} -> capture_generic_failure(version, reason)
      end
    after
      _ = File.rm(xip_path)
    end
  end

  # Distinct Sentry fingerprint so the on-call channel sees ONE
  # alert per session-expiry incident, not N alerts (one per
  # missing version) collapsed into "many things broken."
  defp capture_session_expired(version, reason) do
    Logger.warning("xcode_mirror: Apple session expired",
      version: version,
      reason: reason
    )

    Sentry.capture_message("xcode_mirror.session_expired",
      level: :error,
      fingerprint: ["xcode_mirror", "session_expired"],
      extra: %{
        first_failing_version: version,
        reason: inspect(reason),
        runbook:
          "Refresh with `mise run xcode-mirror:mint-session` on a maintainer Mac; see infra/macos-xcode-image/AGENTS.md."
      }
    )
  end

  defp capture_ghcr_misconfigured(version) do
    Logger.error("xcode_mirror: GHCR credentials not configured",
      version: version
    )

    Sentry.capture_message("xcode_mirror.ghcr_misconfigured",
      level: :error,
      fingerprint: ["xcode_mirror", "ghcr_misconfigured"],
      extra: %{
        version: version,
        runbook:
          "Set TUIST_XCODE_MIRROR_GHCR_USERNAME / TUIST_XCODE_MIRROR_GHCR_TOKEN via the xcode-mirror External Secret."
      }
    )
  end

  defp capture_oras_missing(version) do
    Logger.error("xcode_mirror: oras binary not on PATH inside pod",
      version: version
    )

    Sentry.capture_message("xcode_mirror.oras_unavailable",
      level: :error,
      fingerprint: ["xcode_mirror", "oras_unavailable"],
      extra: %{
        version: version,
        runbook: "Pod image regression — `oras` should be installed by server/Dockerfile."
      }
    )
  end

  defp capture_generic_failure(version, reason) do
    Logger.warning("xcode_mirror: mirror attempt failed",
      version: version,
      reason: inspect(reason)
    )

    Sentry.capture_message("xcode_mirror.mirror_failed",
      level: :warning,
      fingerprint: ["xcode_mirror", "mirror_failed", inspect(reason)],
      extra: %{
        version: version,
        reason: inspect(reason)
      }
    )
  end

  defp mirror_mode do
    Tuist.Environment.xcode_mirror_mode() || default_mode()
  end

  # Phase rollout: ship Phase 2 with mode="observe" baked in as
  # the default. Phase 3 flips the chart values to "mirror" for
  # the production-only env once the Apple-API stability has been
  # validated for a couple of weeks.
  defp default_mode, do: "observe"
end
