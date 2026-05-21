defmodule Tuist.XcodeMirror.Pusher do
  @moduledoc """
  Shell out to the `oras` CLI to push a downloaded .xip as an OCI
  artifact to `ghcr.io/tuist/xcode-xips:<version>`.

  ## Why oras instead of native Elixir

  The OCI distribution-spec push flow has half a dozen steps —
  initiate-upload, chunked PUTs (or monolithic POST for blobs that
  fit), commit, manifest PUT. We could implement it with `Req`
  but the implementation would duplicate ~500 lines of well-trodden
  code in `oras`, and the surface area for "GHCR changed something"
  bugs is wider. `oras` is a stable, single-binary CLI distributed
  by the OCI working group; shelling out from a controlled `MuonTrap.cmd`
  call is the boring choice.

  ## Auth

  `oras login` writes credentials to `~/.docker/config.json`. We
  do a one-shot `oras login` per push to keep auth state explicit
  and avoid surprises from concurrent workers. The
  `TUIST_XCODE_MIRROR_GHCR_USERNAME` / `TUIST_XCODE_MIRROR_GHCR_TOKEN`
  env vars carry the credentials; the token needs `write:packages`
  on the tuist org. Without auth configured, `push/2` returns
  `{:error, :no_credentials}` immediately — same shape the
  downloader uses for missing session cookies.

  ## Failure modes

    * `:no_credentials` — env vars empty / unset.
    * `:oras_unavailable` — the binary isn't on `PATH` (Docker
      image regression). Caller should alert; a redeploy is
      needed to recover.
    * `{:login_failed, output}` — auth dance returned non-zero
      from `oras login`. The output goes into the error tuple so
      the alert can carry it.
    * `{:push_failed, output}` — `oras push` returned non-zero.
  """

  alias Tuist.Environment

  require Logger

  @oras_binary "oras"

  @doc """
  Push `xip_path` to `ghcr.io/tuist/xcode-xips:<version>`.

  The pushed manifest uses the `application/vnd.tuist.xcode-xip`
  artifact type so the worker (and any downstream tooling) can
  verify the tag is a real .xip and not some unrelated artifact
  that landed under the same name. The blob carries Apple's own
  media type, `application/x-pkcs7-mime`.
  """
  def push(version, xip_path, opts \\ []) do
    with :ok <- ensure_oras_available(),
         {:ok, username, token} <- credentials(opts),
         :ok <- login(username, token),
         :ok <- do_push(version, xip_path) do
      {:ok, "ghcr.io/tuist/xcode-xips:#{version}"}
    end
  end

  defp ensure_oras_available do
    if System.find_executable(@oras_binary) do
      :ok
    else
      {:error, :oras_unavailable}
    end
  end

  defp credentials(opts) do
    username =
      Keyword.get(opts, :ghcr_username) ||
        Environment.get([:xcode_mirror, :ghcr_username], Environment.secrets()) ||
        "tuist-bot"

    token =
      Keyword.get(opts, :ghcr_token) ||
        Environment.get([:xcode_mirror, :ghcr_token], Environment.secrets())

    if is_binary(token) and token != "" do
      {:ok, username, token}
    else
      {:error, :no_credentials}
    end
  end

  defp login(username, token) do
    # Pipe the token via stdin rather than the `--password` flag so
    # it never lands in the process table. The `password-stdin`
    # form is the documented pattern for both `docker login` and
    # `oras login`.
    case MuonTrap.cmd(@oras_binary, ["login", "ghcr.io", "--username", username, "--password-stdin"],
           into: "",
           stderr_to_stdout: true,
           input: token
         ) do
      {_out, 0} -> :ok
      {output, _code} -> {:error, {:login_failed, output}}
    end
  end

  defp do_push(version, xip_path) do
    args = [
      "push",
      "--artifact-type",
      "application/vnd.tuist.xcode-xip",
      "ghcr.io/tuist/xcode-xips:#{version}",
      "#{xip_path}:application/x-pkcs7-mime"
    ]

    case MuonTrap.cmd(@oras_binary, args, into: "", stderr_to_stdout: true) do
      {_out, 0} ->
        Logger.info("xcode_mirror: pushed Xcode #{version}",
          tag: "ghcr.io/tuist/xcode-xips:#{version}"
        )

        :ok

      {output, code} ->
        Logger.warning("xcode_mirror: oras push failed",
          version: version,
          exit_code: code,
          output: output
        )

        {:error, {:push_failed, output}}
    end
  end
end
