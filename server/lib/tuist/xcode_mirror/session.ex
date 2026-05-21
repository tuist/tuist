defmodule Tuist.XcodeMirror.Session do
  @moduledoc """
  The Apple developer-portal session, captured as a cookie jar in
  1Password and synced into the server pod via External Secrets.

  ## Why cookies and not API keys

  Apple's `developer.apple.com` download endpoints predate the App
  Store Connect API (which is JWT-based) and never got retrofitted
  with machine credentials. App-specific passwords scope to
  legacy iCloud surfaces only; ASC API keys scope to App Store
  Connect only. The only path that authenticates Xcode .xip
  downloads is the post-2FA web session cookies — same trick
  Fastlane's `FASTLANE_SESSION`, Cirrus's image builders, and
  xcodes itself rely on.

  ## Format

  The `TUIST_XCODE_MIRROR_SESSION_COOKIES` env var holds a JSON
  object mapping cookie names to values:

      {
        "myacinfo": "DAWTKNV28...",
        "dqsid": "abc...",
        "aidsp":  "..."
      }

  Captured locally by the `mise run xcode-mirror:mint-session`
  task, which reads xcodes' keychain entry and writes the JSON
  straight into the 1Password item via `op item edit`.

  ## Lifetime

  Apple's developer-portal sessions last ~30 days in CI scenarios
  (longer when used regularly, but the ceiling is opaque). When
  the cookies expire, Apple's CDN returns 401 / 403 on download.
  The worker detects that and emits
  `xcode_mirror.session_expired` to Sentry with a runbook link to
  the `mint-session` task; refresh from any maintainer's Mac, no
  SSH required.
  """

  alias Tuist.Environment

  @doc """
  Load the session cookies from the configured env var.

  Returns `{:ok, %{"myacinfo" => "...", ...}}` when a non-empty
  JSON object is configured, `{:error, :missing}` when the env
  var is empty or unset (Phase 2 ticks in dev / staging without
  the secret wired up — diff still computes, downloads no-op),
  `{:error, {:parse_error, reason}}` when the env var holds
  malformed JSON.
  """
  def load(opts \\ []) do
    raw =
      Keyword.get(opts, :raw) ||
        Environment.get([:xcode_mirror, :session_cookies], Environment.secrets())

    if is_nil(raw) or raw == "" do
      {:error, :missing}
    else
      case JSON.decode(raw) do
        {:ok, map} when is_map(map) and map_size(map) > 0 ->
          # Stringify any odd value shapes — Apple's cookies are
          # always strings but a maintainer's hand-edit could
          # smuggle in an integer or boolean.
          {:ok, Map.new(map, fn {k, v} -> {to_string(k), to_string(v)} end)}

        {:ok, _} ->
          {:error, {:parse_error, :empty_object}}

        {:error, reason} ->
          {:error, {:parse_error, reason}}
      end
    end
  end

  @doc """
  Format a cookie map as a `Cookie:` header value for outgoing
  HTTP requests against Apple's CDN.

  `to_cookie_header(%{"myacinfo" => "DAW", "dqsid" => "abc"})`
  produces `"myacinfo=DAW; dqsid=abc"` (order is map traversal
  order; servers don't care).
  """
  def to_cookie_header(cookies) when is_map(cookies) do
    Enum.map_join(cookies, "; ", fn {k, v} -> "#{k}=#{v}" end)
  end
end
