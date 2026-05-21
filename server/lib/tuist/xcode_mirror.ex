defmodule Tuist.XcodeMirror do
  @moduledoc """
  Mirror of Apple's developer-portal Xcode .xips into our own
  GHCR-backed OCI registry (`ghcr.io/tuist/xcode-xips:<version>`).

  ## Why

  The `macos-xcode-image` build workflow used to drive `xcodes
  download` against `developer.apple.com` directly, authenticating
  with a long-lived session in the build host's login keychain.
  That model broke once the vm-image-builder Mac minis moved into
  the CAPI-managed fleet: any Node rotation wipes the keychain,
  and the failure surfaces as a confusing CI error instead of an
  obvious "session needs refreshing" signal.

  This module decouples Apple auth from CI by mirroring every
  released Xcode .xip into our own registry. The build workflow
  does `oras pull ghcr.io/tuist/xcode-xips:<version>` instead of
  hitting Apple; the only place the Apple session lives is the
  cookie jar stored in 1Password and synced into the server's
  env via External Secrets.

  ## Pieces

    * `Tuist.XcodeMirror.AppleReleases` — fetches the canonical
      list of released Xcodes from the public
      [xcodereleases.com](https://xcodereleases.com) data feed. No
      Apple-auth required for the *listing* — the only place we
      need authenticated Apple access is the .xip download itself.

    * `Tuist.XcodeMirror.Registry` — talks to our own GHCR
      `xcode-xips` repository over the standard OCI Distribution
      API. Lists tags so the reconciler knows what's already
      mirrored.

    * `Tuist.XcodeMirror.Session` — parses the cookie jar from the
      `TUIST_XCODE_MIRROR_SESSION_COOKIES` env var into a form the
      downloader can attach to Apple-CDN HTTP requests.

    * `Tuist.XcodeMirror.Workers.ReconcileWorker` — the Oban worker
      that ticks every 6 hours, diffs Apple's list against our
      mirror, and (in Phase 3) downloads + pushes anything missing.

  ## Phased rollout

  This file ships in three phases (deliberately, so the cookie
  replay + Apple-API stability gets validated in prod before we
  trust the worker with multi-GB transfers):

    * **Phase 2 (this commit):** the worker computes the diff and
      logs / metric-emits the missing versions. No downloads, no
      pushes. Validates that `AppleReleases` and `Registry` work
      against real Apple + real GHCR without burning bandwidth on
      cookie failures.

    * **Phase 3:** download missing .xips from Apple's CDN with
      session cookies; push to GHCR via the `oras` CLI; emit
      `xcode_mirror.session_expired` Sentry messages on 401s with a
      runbook link.

  In both phases the operator break-glass remains the
  `mise run xcode-mirror:upload <version>` task — manual mint +
  oras push from any maintainer's Mac.
  """

  alias Tuist.XcodeMirror.AppleReleases
  alias Tuist.XcodeMirror.Registry

  require Logger

  @doc """
  Compute the set of Xcode versions Apple has released but our
  mirror is missing.

  Returns `{:ok, [version, ...]}` on success, where each `version`
  is the patch-form string (`"26.4.1"`, `"26.5"`) — same shape as
  the `xcode_version` Packer variable consumed downstream.

  Errors from either upstream propagate as `{:error, reason}`
  without partial progress; the worker treats this as a tick to
  retry next cycle.
  """
  def missing_versions(opts \\ []) do
    with {:ok, apple} <- AppleReleases.list_released(opts),
         {:ok, mirrored} <- Registry.list_mirrored_tags(opts) do
      mirrored_set = MapSet.new(mirrored)

      missing =
        apple
        |> Enum.reject(&MapSet.member?(mirrored_set, &1))
        |> Enum.sort_by(&parse_version/1, :desc)

      {:ok, missing}
    end
  end

  # Cheap version parser for sorting newest-first. Tolerates the
  # two-segment ("26.5") and three-segment ("26.4.1") forms; Apple
  # has occasionally shipped four-segment betas but the worker
  # treats those as opaque strings — only the sort order matters.
  defp parse_version(version) do
    version
    |> String.split(".")
    |> Enum.map(&parse_int/1)
  end

  defp parse_int(segment) do
    case Integer.parse(segment) do
      {n, _} -> n
      :error -> 0
    end
  end
end
