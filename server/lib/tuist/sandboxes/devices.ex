defmodule Tuist.Sandboxes.Devices do
  @moduledoc """
  The devices of a sandbox and its screen, for agents that reach the sandbox
  only through MCP: list, boot and capture devices, install and launch an app
  built in the sandbox, and open a URL.

  Today a device is an iOS (or other Apple platform) simulator on a macOS
  sandbox. The contract is named for devices so Android emulators can join it
  later as another `platform`; until then a Linux sandbox answers
  `:devices_unsupported`.

  Each action runs one fixed script with `Sandboxes.exec/3`, which resumes a
  paused sandbox first. The caller's values (device, app ID, path, URL) reach
  the script only as environment variables, never as shell text, so none of
  this is a general `exec`. The scripts answer failures the caller can act on
  with their own exit statuses, which become the reasons
  `Tuist.Sandboxes.Query.error/1` describes.

  `tuist sandbox screenshot` (`cli/Sources/TuistSandboxCommand`) captures the
  same way but keeps the full-size PNG; here the image is scaled to at most
  1600 pixels on its longer side and sent as a JPEG, since it goes into the
  agent's context and the synchronous exec caps stdout at 1 MiB.
  """
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Commands
  alias Tuist.Sandboxes.Sandbox

  @unsupported 3
  @not_booted 4
  @device_not_found 5
  @app_not_found 6
  @max_side 1600
  @boot_wait_seconds 40

  @prelude """
  set -u
  [ "$(uname)" = Darwin ] || exit #{@unsupported}
  """

  # simctl waits a long time for the screen of a device that is not booted
  # before it fails, so the capture checks first. A device matches by its
  # whole name or UDID: `iPhone 1` must not match `iPhone 17`.
  @require_booted """
  booted="$(xcrun simctl list devices booted | grep '(Booted)')"
  if [ "$TUIST_DEVICE" = booted ]; then [ -n "$booted" ] || exit #{@not_booted}
  else printf '%s\\n' "$booted" | grep -qF -e "    $TUIST_DEVICE (" -e "($TUIST_DEVICE)" || exit #{@not_booted}; fi
  """

  @screenshot_script @prelude <>
                       """
                       png="$(mktemp /tmp/tuist-screenshot.XXXXXX)"; jpg="$png.jpg"
                       trap 'rm -f "$png" "$jpg"' EXIT
                       if [ "$TUIST_TARGET" = screen ]; then
                         screencapture -x -t png "$png" >&2 || exit 1
                       else
                       #{@require_booted}  xcrun simctl io "$TUIST_DEVICE" screenshot --type=png "$png" >&2 || exit 1
                       fi
                       sips -Z #{@max_side} -s format jpeg -s formatOptions 80 "$png" --out "$jpg" >&2 || exit 1
                       sips -g pixelWidth -g pixelHeight "$jpg" | awk '/pixelWidth/ {w=$2} /pixelHeight/ {h=$2} END {print w, h}'
                       base64 < "$jpg"
                       """

  @list_script @prelude <> "xcrun simctl list devices available -j\n"

  @boot_script @prelude <>
                 """
                 xcrun simctl list devices available | grep -qF -e "    $TUIST_DEVICE (" -e "($TUIST_DEVICE)" || exit #{@device_not_found}
                 out="$(xcrun simctl boot "$TUIST_DEVICE" 2>&1)" || case "$out" in *"current state: Booted"*) ;; *) echo "$out" >&2; exit 1 ;; esac
                 open -a "$(xcode-select -p)/Applications/Simulator.app" >/dev/null 2>&1 || true
                 for _ in $(seq #{@boot_wait_seconds}); do
                   xcrun simctl list devices | grep -F -e "    $TUIST_DEVICE (" -e "($TUIST_DEVICE)" | grep -q '(Booted)' && break
                   sleep 1
                 done
                 xcrun simctl list devices available -j
                 """

  @launch_script @prelude <>
                   @require_booted <>
                   """
                   app="${TUIST_APP_ID:-}"
                   if [ -n "${TUIST_APP_PATH:-}" ]; then
                     [ -d "$TUIST_APP_PATH" ] || exit #{@app_not_found}
                     xcrun simctl install "$TUIST_DEVICE" "$TUIST_APP_PATH" >&2 || exit 1
                     [ -n "$app" ] || app="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$TUIST_APP_PATH/Info.plist")" || exit 1
                   fi
                   xcrun simctl get_app_container "$TUIST_DEVICE" "$app" >/dev/null 2>&1 || exit #{@app_not_found}
                   xcrun simctl launch --terminate-running-process "$TUIST_DEVICE" "$app" >&2 || exit 1
                   printf '%s' "$app"
                   """

  @open_url_script @prelude <> @require_booted <> ~s(xcrun simctl openurl "$TUIST_DEVICE" "$TUIST_URL" >&2 || exit 1\n)

  # The image's newest Pro iPhone (iPhone 18 Pro on Xcode 27.2), else its
  # first iPhone.
  @background_boot_script @prelude <>
                            """
                            available="$(xcrun simctl list devices available)"
                            device="$(printf '%s\\n' "$available" | sed -nE 's/^ +iPhone ([0-9]+) Pro \\(([0-9A-F-]{36})\\).*/\\1 \\2/p' | sort -rn | head -1 | cut -d' ' -f2)"
                            [ -n "$device" ] || device="$(printf '%s\\n' "$available" | sed -nE 's/^ +iPhone.* \\(([0-9A-F-]{36})\\).*/\\1/p' | head -1)"
                            [ -n "$device" ] || exit #{@device_not_found}
                            xcrun simctl boot "$device" || exit 1
                            xcrun simctl bootstatus "$device" -b >/dev/null
                            """

  @doc false
  def screenshot_script, do: @screenshot_script

  @doc """
  The available devices, each with its `id` (a simulator's UDID), `name`,
  `platform` (such as `ios`), `runtime` (such as `iOS 27.2`) and `state`
  (`Booted`, `Shutdown`, `Booting`).
  """
  def list(%Sandbox{} = sandbox) do
    with {:ok, stdout} <- run(sandbox, @list_script, %{}), do: devices(stdout)
  end

  @doc """
  Boots the device named by `device` (a name or ID) and opens the Simulator
  app, waiting up to #{@boot_wait_seconds} seconds for it to finish booting.
  Booting a booted one succeeds. Returns the device, whose `state` is still
  `Booting` when it took longer.
  """
  def boot(%Sandbox{} = sandbox, device) do
    with {:ok, stdout} <- run(sandbox, @boot_script, %{"TUIST_DEVICE" => device}, @boot_wait_seconds + 15, device),
         {:ok, devices} <- devices(stdout) do
      case Enum.find(devices, &(&1.id == device)) || Enum.find(devices, &(&1.name == device)) do
        nil -> {:error, {:device_not_found, device}}
        found -> {:ok, found}
      end
    end
  end

  @doc """
  Starts booting the image's newest Pro iPhone as a sandbox command and
  answers at once, so a Mac a session builds on has a booted simulator by
  the time its first build ends instead of booting one cold after it: a
  first boot took 20–28 seconds until ready and the Mac stayed busy for
  about a minute after (measured on Xcode 27.2, 2026-11).
  """
  def boot_in_background(%Sandbox{platform: :darwin} = sandbox) do
    Commands.start(sandbox, %{
      command: "/bin/bash",
      args: ["-c", @background_boot_script],
      timeout_ms: to_timeout(minute: 5)
    })
  end

  @doc """
  Launches the app with `app_id` (an iOS bundle ID) on `device` (default: the
  booted one), installing it first from `app_path`, an `.app` in the sandbox,
  when given. A running copy is restarted. Returns the app ID it launched.
  """
  def launch(%Sandbox{} = sandbox, opts) do
    env = %{
      "TUIST_DEVICE" => opts[:device] || "booted",
      "TUIST_APP_ID" => opts[:app_id] || "",
      "TUIST_APP_PATH" => opts[:app_path] || ""
    }

    with {:ok, app_id} <- run(sandbox, @launch_script, env, 120, opts[:device]),
         do: {:ok, %{app_id: app_id, device: env["TUIST_DEVICE"]}}
  end

  @doc "Opens `url` (a web page or the app's deep link) on `device` (default: the booted one)."
  def open_url(%Sandbox{} = sandbox, url, device \\ nil) do
    env = %{"TUIST_DEVICE" => device || "booted", "TUIST_URL" => url}
    with {:ok, _} <- run(sandbox, @open_url_script, env, 60, device), do: {:ok, %{url: url, device: env["TUIST_DEVICE"]}}
  end

  @doc """
  Captures `device` (default: the booted one), or with `target: :screen` the
  sandbox's whole screen, as a JPEG. Returns its base64 `data`, `width` and
  `height`.
  """
  def screenshot(%Sandbox{} = sandbox, opts \\ []) do
    target = Keyword.get(opts, :target, :device)
    device = opts[:device]
    env = %{"TUIST_TARGET" => Atom.to_string(target), "TUIST_DEVICE" => device || "booted"}

    with {:ok, stdout} <- run(sandbox, @screenshot_script, env, 60, device),
         [size, data] <- String.split(stdout, "\n", parts: 2),
         [width, height] <- String.split(size),
         {width, ""} <- Integer.parse(width),
         {height, ""} <- Integer.parse(height),
         data = String.replace(data, ~r/\s/, ""),
         {:ok, _} <- Base.decode64(data) do
      {:ok, %{data: data, mime_type: "image/jpeg", width: width, height: height}}
    else
      {:error, _reason} = error -> error
      _ -> {:error, {:simulator_failed, "The sandbox sent no image."}}
    end
  end

  # Linux sandboxes answer before exec, which would resume a paused one only to fail.
  defp run(sandbox, script, env, timeout_seconds \\ 60, device \\ nil)
  defp run(%Sandbox{platform: :linux}, _script, _env, _timeout_seconds, _device), do: {:error, :devices_unsupported}

  defp run(sandbox, script, env, timeout_seconds, device) do
    case Sandboxes.exec(sandbox, ["/bin/bash", "-c", script], env: env, timeout_ms: timeout_seconds * 1000) do
      {:ok, %{exit_code: 0, stdout: stdout}} -> {:ok, stdout}
      {:ok, %{exit_code: @unsupported}} -> {:error, :devices_unsupported}
      {:ok, %{exit_code: @not_booted}} -> {:error, {:device_not_booted, device}}
      {:ok, %{exit_code: @device_not_found}} -> {:error, {:device_not_found, device}}
      {:ok, %{exit_code: @app_not_found}} -> {:error, :app_not_found}
      {:ok, %{stderr: stderr}} -> {:error, {:simulator_failed, stderr}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp devices(stdout) do
    case JSON.decode(stdout) do
      {:ok, %{"devices" => by_runtime}} ->
        {:ok,
         for {runtime, devices} <- Enum.sort(by_runtime), device <- devices do
           {platform, runtime} = runtime_name(runtime)

           %{
             id: device["udid"],
             name: device["name"],
             platform: platform,
             runtime: runtime,
             state: device["state"]
           }
         end}

      _ ->
        {:error, {:simulator_failed, "simctl listed no devices."}}
    end
  end

  # com.apple.CoreSimulator.SimRuntime.iOS-27-2 -> {"ios", "iOS 27.2"}
  defp runtime_name(identifier) do
    case identifier |> String.split(".") |> List.last() |> String.split("-") do
      [platform | version] when version != [] -> {String.downcase(platform), "#{platform} #{Enum.join(version, ".")}"}
      _ -> {nil, identifier}
    end
  end
end
