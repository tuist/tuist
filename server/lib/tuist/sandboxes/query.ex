defmodule Tuist.Sandboxes.Query do
  @moduledoc """
  Account-scoped public sandbox data and lifecycle actions shared by the
  HTTP API, MCP tools and the CLI, so the three return the same shapes and
  errors. Shapes are in `Tuist.Sandboxes.Schemas`.
  """
  alias Tuist.Accounts.Account
  alias Tuist.RateLimit
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Analytics
  alias Tuist.Sandboxes.ClaudeCodeSnapshots
  alias Tuist.Sandboxes.Commands
  alias Tuist.Sandboxes.Concurrency
  alias Tuist.Sandboxes.Devices
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.Schemas

  require Logger

  @max_range_seconds 90 * 86_400
  @no_filters %{"search" => nil, "status" => nil, "vcpus" => nil}
  @create_fields ~w(platform template xcode_version vcpus memory_mb memory_limit_mb workspace_gb lifetime_seconds)
  @capacity_wait_ms 25_000
  @creates_per_minute 10

  def run(:list, %Account{} = account, params) do
    with {:ok, page, size} <- pagination(params),
         {:ok, opts} <- filters(params) do
      count = Sandboxes.count_sandboxes(account, opts)

      {:ok,
       %{
         sandboxes:
           account
           |> Sandboxes.list_sandboxes(opts ++ [limit: size, offset: (page - 1) * size])
           |> Enum.map(&sandbox/1),
         pagination_metadata: metadata(page, size, count)
       }}
    end
  end

  # The changeset validates each platform's shapes; omitted fields take the platform's defaults.
  # A macOS sandbox for a `repository` boots from its Claude Code macOS
  # snapshot when one is ready, and has one built otherwise.
  #
  # When no host has room, the create waits for one inside the request
  # (25 seconds, retrying placement every few seconds) before it
  # answers `:no_capacity`, so an agent's create succeeds as soon as a CI job
  # frees a Mac instead of after its next retry. The wait fits a Mac boot
  # inside MCP clients' 60-second tool timeout. Creates are also limited per
  # account (`@creates_per_minute`), so agents retrying in a loop are slowed
  # down before they reach admission.
  def run(:create, account, params) do
    attrs = for {key, value} <- params, key in @create_fields, into: %{}, do: {String.to_existing_atom(key), value}
    attrs = put_guarantee(attrs, params["guaranteed_vcpus"])
    # Sandboxes created here are the caller's to end; a lifetime ends the
    # ones they forget (`Sandboxes.expire_sandboxes/0`).
    attrs = Map.put_new(attrs, :lifetime_seconds, Sandbox.default_lifetime_seconds())

    with :ok <- limit_creates(account),
         {:ok, source} <- ClaudeCodeSnapshots.mac_source(account, params["repository"], attrs),
         attrs = if(source, do: Map.put(attrs, :repository, source.repository), else: attrs),
         {:ok, created} <-
           Sandboxes.create_sandbox(account, attrs,
             from_disk_snapshot: source && source.snapshot,
             capacity_wait_ms: capacity_wait_ms()
           ) do
      ClaudeCodeSnapshots.request_mac_build(source)
      held = kept(created)
      if source, do: boot_device_in_background(held)
      {:ok, sandbox(held)}
    end
  end

  def run(:show, account, params) do
    with {:ok, found} <- find(account, params), do: {:ok, sandbox(found)}
  end

  def run(:pause, account, params), do: transition(account, params, &Sandboxes.pause/1)
  def run(:resume, account, params), do: transition(account, params, &resume_and_keep/1)

  def run(:extend, account, params) do
    with {:ok, found} <- find(account, params),
         {:ok, extended} <- Sandboxes.extend(found, params["lifetime_seconds"]) do
      {:ok, sandbox(extended)}
    end
  end

  def run(:archive, account, params) do
    with {:ok, found} <- find(account, params),
         :ok <- Sandboxes.archive(found) do
      {:ok, sandbox(found)}
    end
  end

  def run(:delete, account, params) do
    with {:ok, found} <- find(account, params),
         {:ok, _deleted} <- Sandboxes.delete(found) do
      {:ok, %{id: found.id, deleted: true}}
    end
  end

  # The device actions run fixed scripts in the sandbox (`Devices`); the
  # caller's values only reach them as environment variables.
  def run(:devices, account, params) do
    with {:ok, found} <- find(account, params),
         {:ok, devices} <- Devices.list(found),
         do: {:ok, %{devices: devices}}
  end

  def run(:boot_device, account, params) do
    with {:ok, found} <- find(account, params), do: Devices.boot(found, params["device"])
  end

  def run(:launch_app, account, params) do
    with {:ok, found} <- find(account, params) do
      Devices.launch(found, device: params["device"], app_id: params["app_id"], app_path: params["app_path"])
    end
  end

  def run(:open_url, account, params) do
    with {:ok, found} <- find(account, params), do: Devices.open_url(found, params["url"], params["device"])
  end

  def run(:screenshot, account, params) do
    target = if params["target"] == "screen", do: :screen, else: :device

    with {:ok, found} <- find(account, params),
         {:ok, shot} <- Devices.screenshot(found, target: target, device: params["device"]) do
      {:ok,
       Map.merge(shot, %{
         target: Atom.to_string(target),
         device: if(target == :device, do: params["device"] || "booted")
       })}
    end
  end

  def run(:analytics, account, params) do
    with {:ok, {start, finish}} <- period(params) do
      overview = Analytics.overview(account.id, start_datetime: start, end_datetime: finish)
      usage = Analytics.compute(account.id, start_datetime: start, end_datetime: finish)
      in_use = Concurrency.usage(account.id)
      concurrency = overview.concurrency

      {:ok,
       %{
         period: %{start: iso(start), end: iso(finish)},
         bucket: Atom.to_string(Analytics.bucket_for_window(start, finish)),
         vcpu_hours: usage.vcpu_hours,
         memory_gib_hours: usage.memory_gib_hours,
         created: %{
           count: overview.created.count,
           trend: overview.created.trend,
           points: points(overview.created.dates, &%{value: Enum.at(overview.created.values, &1)})
         },
         session_duration: duration(overview.session_duration),
         setup: duration(overview.setup),
         time_to_start: duration(overview.time_to_start),
         concurrency: %{
           limits: %{
             vcpus: account.sandbox_vcpus_limit,
             memory_gb: account.sandbox_memory_gb_limit * 1.0
           },
           # Guarantees can be fractions of a vCPU; the API's vCPUs are whole.
           in_use: %{
             vcpus: ceil(in_use.vcpus),
             memory_gb: Float.round(in_use.memory_mb / 1024, 1)
           },
           points:
             points(
               concurrency.dates,
               &%{
                 vcpus: ceil(Enum.at(concurrency.vcpus, &1)),
                 memory_gb: Enum.at(concurrency.memory_gb, &1) * 1.0
               }
             )
         }
       }}
    end
  end

  # Every 503 comes after the server already waited for a node or for
  # capacity, so an immediate retry only repeats that wait. The hint is
  # longer than any CLI retry budget (`RetryMiddleware` waits at most 30
  # seconds per retry, 10 retries at most), so released CLIs report it at
  # once, and it is what the messages tell agents to wait.
  @unavailable_retry_after_seconds 300

  @doc """
  The answer to an error `run/3` (or another sandbox action) returned: its
  HTTP `status`, a stable machine-readable `code` clients branch on, the
  human `message`, and for some codes `retry_after` in seconds, which the API
  sends as `retry-after`. Codes never change meaning; messages may.
  """
  def error(reason) do
    {status, code, message} = describe(reason)
    answer = %{status: status, code: code, message: message}

    cond do
      match?({:rate_limited, _seconds}, reason) -> Map.put(answer, :retry_after, elem(reason, 1))
      status == :service_unavailable -> Map.put(answer, :retry_after, @unavailable_retry_after_seconds)
      true -> answer
    end
  end

  defp describe({:invalid_state, state}), do: {:conflict, "invalid_state", "The sandbox is #{state}."}
  defp describe(:not_found), do: {:not_found, "not_found", "Sandbox not found."}

  defp describe(:integration_sandbox),
    do:
      {:forbidden, "forbidden",
       "The sandbox serves an agent environment, an Amp Orb or remote execution. Only account administrators can run commands in it or reach its files."}

  defp describe({:invalid_cwd, cwd}),
    do: {:bad_request, "invalid_cwd", "The working directory #{cwd} does not exist in the sandbox or is not a directory."}

  defp describe(:invalid_parameters),
    do:
      {:bad_request, "invalid_parameters",
       "Invalid identifier, pagination, filter, sorting or time range. Use an ordered range of at most 90 days ending no later than now."}

  defp describe(:no_node), do: {:service_unavailable, "no_node", "No sandbox node with the template ready is connected."}

  defp describe(:sandbox_concurrency_limit),
    do:
      {:too_many_requests, "account_limit",
       "The account is using all of its sandbox CPU or memory. Pause or delete a sandbox it no longer needs, or ask an account admin to raise the limit; retrying does not help until then."}

  defp describe({:platform_not_enabled, platform}) do
    name = if platform == :darwin, do: "macOS", else: "Linux"

    {:forbidden, "platform_not_enabled",
     "#{name} sandboxes are not enabled for this account yet. Retrying does not help; request access at contact@tuist.dev."}
  end

  defp describe({:rate_limited, seconds}),
    do:
      {:too_many_requests, "rate_limited",
       "The account created too many sandboxes in the last minute. Wait #{seconds} seconds before creating another, and reuse a sandbox instead of creating one per command."}

  defp describe(:sandbox_account_busy),
    do:
      {:conflict, "account_busy",
       "Another request was changing this account's sandboxes and held them for several seconds. Retry in a few seconds."}

  defp describe(:busy), do: {:conflict, "sandbox_busy", "An agent turn or another command is running in the sandbox."}

  defp describe(:invalid_command),
    do:
      {:bad_request, "invalid_command",
       "Invalid command: it needs a non-empty command, string arguments, environment names of letters, digits and underscores, and stdin data of at most 256 KiB in base64."}

  defp describe(:stdin_not_attached),
    do: {:conflict, "stdin_not_attached", "The command was not started with stdin attached."}

  defp describe(:stdin_closed), do: {:conflict, "stdin_closed", "The command's stdin is closed."}

  defp describe(:no_lifetime),
    do:
      {:conflict, "no_lifetime",
       "The sandbox has no lifetime to extend: it belongs to an integration, such as an Amp Orb or a Claude session, which ends it, or it was created before sandboxes had lifetimes."}

  defp describe(:stdin_offset_mismatch),
    do:
      {:conflict, "stdin_offset_mismatch",
       "The write does not continue the command's stdin: its offset is not the number of bytes stdin holds."}

  defp describe(:locked), do: {:conflict, "locked", "Another operation on the sandbox is in progress."}

  defp describe(:command_id_taken),
    do: {:conflict, "command_id_taken", "Another command already uses this id. Choose a new id for a new command."}

  # The fleet, not the account, is full. A create has already waited for room
  # (`capacity_wait_ms/0`), so a retry in a loop only adds load.
  defp describe(:no_capacity),
    do:
      {:service_unavailable, "fleet_busy",
       "Every sandbox host is busy right now; the server already waited #{div(capacity_wait_ms(), 1000)} seconds for one to free up. Macs are shared with CI jobs, which take priority and usually free up within minutes. Do not retry in a loop: tell the user the hosts are busy and try once more in about #{div(@unavailable_retry_after_seconds, 60)} minutes. The default shape fits more hosts. `tuist sandbox create --wait-timeout 5m` waits for a host for up to 5 minutes instead."}

  # A paused macOS sandbox resumes warm only on the Mac that holds it, which
  # it shares with CI. A refused resume also moves it to storage, so a later
  # resume can cold-boot it on another Mac.
  defp describe({:host_busy, :ci}),
    do:
      {:service_unavailable, "host_busy_ci",
       "The Mac this sandbox runs on is busy with CI jobs, which take priority. The sandbox resumes when a CI job finishes there, or on another Mac once it has moved there; a move keeps its files but not its running processes."}

  defp describe({:host_busy, :full}),
    do:
      {:service_unavailable, "host_busy_full",
       "The Mac this sandbox runs on has no CPU, memory or VM slot free; CI jobs and other sandboxes are using them. The sandbox resumes when one frees up there, or on another Mac once it has moved there; a move keeps its files but not its running processes."}

  defp describe({:host_busy, :no_grant}),
    do:
      {:service_unavailable, "host_busy_no_grant",
       "The Mac this sandbox runs on is waiting for the CI scheduler to confirm it has room for sandboxes."}

  defp describe({:host_busy, :not_connected}),
    do: {:service_unavailable, "host_not_connected", "The Mac this sandbox runs on is not connected."}

  defp describe({:host_busy, :replaced}),
    do:
      {:service_unavailable, "host_replaced",
       "The Mac this sandbox ran on was replaced, so the sandbox can't resume. Create a new sandbox."}

  defp describe(:archive_store_unavailable),
    do:
      {:service_unavailable, "archive_unavailable",
       "The storage that holds this sandbox's archive is not configured on this server, so the archive can't be reached."}

  defp describe(:not_connected), do: {:service_unavailable, "node_not_connected", "The sandbox's node is not connected."}

  defp describe(:node_disconnected),
    do: {:service_unavailable, "node_disconnected", "The sandbox's node disconnected during the operation."}

  defp describe(:timeout), do: {:gateway_timeout, "node_timeout", "The sandbox's node did not answer in time."}

  defp describe(:snapshot_not_saved),
    do: {:service_unavailable, "snapshot_not_saved", "The Orb paused, but its project snapshot could not be saved."}

  defp describe(:devices_unsupported),
    do:
      {:bad_request, "devices_unsupported",
       "This sandbox runs no devices: today only macOS sandboxes run iOS simulators, and Android emulators are not supported yet. Create a macOS sandbox with `create_sandbox` and `platform: darwin`."}

  defp describe({:device_not_booted, nil}),
    do:
      {:conflict, "device_not_booted",
       "No device is booted in the sandbox. Boot one with `boot_sandbox_device` (`list_sandbox_devices` lists them), or capture the whole screen with `target: screen`."}

  defp describe({:device_not_booted, device}),
    do:
      {:conflict, "device_not_booted",
       "The device #{device} is not booted in the sandbox. Boot it with `boot_sandbox_device`; `list_sandbox_devices` lists the devices and their states."}

  defp describe({:device_not_found, device}),
    do:
      {:not_found, "device_not_found",
       "The sandbox has no available device named #{device}. Pass a name or ID that `list_sandbox_devices` returns."}

  defp describe(:app_not_found),
    do:
      {:not_found, "app_not_found",
       "The app is not installed on the device, or `app_path` is not an .app in the sandbox. Build it there, for example with `tuist sandbox exec`, and pass the built .app's path as `app_path`."}

  defp describe({:simulator_failed, output}) do
    output = output |> String.trim() |> String.slice(-4000, 4000)
    {:bad_gateway, "simulator_failed", if(output == "", do: "simctl failed.", else: "simctl failed: #{output}")}
  end

  defp describe(%Ecto.Changeset{} = changeset), do: {:bad_request, "invalid_request", changeset_message(changeset)}

  defp describe(reason) when is_binary(reason),
    do: {:bad_gateway, "node_rejected", "The sandbox node rejected the operation: #{reason}"}

  defp describe(reason), do: {:internal_server_error, "internal_error", "Sandbox operation failed: #{inspect(reason)}"}

  @doc "Every code `error/1` answers, for the API and MCP schemas."
  def error_codes,
    do:
      ~w(invalid_state not_found forbidden invalid_cwd invalid_parameters no_node account_limit platform_not_enabled rate_limited account_busy sandbox_busy invalid_command stdin_not_attached stdin_closed stdin_offset_mismatch locked no_lifetime command_id_taken fleet_busy host_busy_ci host_busy_full host_busy_no_grant host_not_connected host_replaced archive_unavailable node_not_connected node_disconnected node_timeout snapshot_not_saved devices_unsupported device_not_booted device_not_found app_not_found simulator_failed invalid_request node_rejected internal_error)

  defp capacity_wait_ms,
    do: :tuist |> Application.get_env(__MODULE__, []) |> Keyword.get(:capacity_wait_ms, @capacity_wait_ms)

  defp limit_creates(account) do
    case RateLimit.hit("sandboxes:create:account:#{account.id}",
           limit: @creates_per_minute,
           window: to_timeout(minute: 1),
           failure_policy: :local
         ) do
      {:allow, _count} -> :ok
      {:deny, retry_after_ms} -> {:error, {:rate_limited, max(1, div(retry_after_ms + 999, 1000))}}
    end
  end

  # vCPUs to millicores; anything else reaches the changeset as is, which
  # refuses it.
  defp put_guarantee(attrs, nil), do: attrs
  defp put_guarantee(attrs, vcpus) when is_number(vcpus), do: Map.put(attrs, :guaranteed_cpu_milli, round(vcpus * 1000))
  defp put_guarantee(attrs, vcpus), do: Map.put(attrs, :guaranteed_cpu_milli, vcpus)

  @doc """
  The public fields of a sandbox, with the status the dashboard shows.
  """
  def sandbox(%Sandbox{} = sandbox) do
    sandbox
    |> Map.take([
      :id,
      :state,
      :platform,
      :resident,
      :template,
      :template_tag,
      :vcpus,
      :memory_mb,
      :memory_limit_mb,
      :workspace_gb,
      :node_name,
      :hostname,
      :agent_environment_id,
      :anthropic_session_id,
      :amp_orb_id,
      :residency_work_id,
      :last_active_at,
      :paused_at,
      :archived_at,
      :archive_bytes,
      :lifetime_seconds,
      :expires_at,
      :error_message,
      :inserted_at,
      :updated_at
    ])
    |> Map.put(:status, status(sandbox))
    |> Map.put(:guaranteed_vcpus, Sandbox.vcpus(Sandbox.guaranteed_cpu_milli(sandbox)))
  end

  defp status(%Sandbox{state: :running, residency_work_id: work}) when is_binary(work), do: "active"
  defp status(%Sandbox{state: :running}), do: "idle"
  defp status(%Sandbox{state: :creating}), do: "starting"
  defp status(%Sandbox{state: :error}), do: "failed"
  defp status(%Sandbox{state: state}), do: Atom.to_string(state)

  defp transition(account, params, fun) do
    with {:ok, found} <- find(account, params),
         {:ok, updated} <- fun.(found) do
      {:ok, sandbox(updated)}
    end
  end

  defp resume_and_keep(sandbox) do
    with {:ok, resumed} <- Sandboxes.resume(sandbox), do: {:ok, kept(resumed)}
  end

  # A macOS sandbox started here is about to run the caller's commands, so
  # it takes their session lease. A running VM needs no grant for it; the
  # sandbox is still returned when the lease is refused, such as when its
  # host was replaced, and the next command tries again.
  defp kept(sandbox) do
    case Commands.keep(sandbox) do
      {:ok, kept} -> kept
      {:error, _reason} -> sandbox
    end
  end

  # A repository's Mac is a session's build machine, which tests on a
  # simulator next: it boots one while the session syncs and builds. The
  # create succeeds without it.
  defp boot_device_in_background(sandbox) do
    case Devices.boot_in_background(sandbox) do
      {:ok, _command} ->
        :ok

      {:error, reason} ->
        Logger.warning("sandboxes: background simulator boot not started",
          sandbox_id: sandbox.id,
          reason: inspect(reason)
        )
    end
  end

  defp find(account, params) do
    with {:ok, id} <- uuid(params["sandbox_id"]) do
      Sandboxes.get_sandbox(account, id)
    end
  end

  # An identifier that is not a UUID names no sandbox.
  defp uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp pagination(params) do
    page = Map.get(params, "page", 1)
    size = Map.get(params, "page_size", 20)

    if is_integer(page) and page in 1..100_000 and is_integer(size) and size in 1..100,
      do: {:ok, page, size},
      else: {:error, :invalid_parameters}
  end

  # The API says `identifier` rather than `name`: generated Kotlin enums cannot have an entry called `name`.
  defp sort_field("identifier"), do: :name
  defp sort_field(sort), do: String.to_existing_atom(sort)

  defp filters(params) do
    sort = Map.get(params, "sort_by", "created")
    order = Map.get(params, "sort_order", if(sort == "identifier", do: "asc", else: "desc"))
    %{"search" => search, "status" => status, "vcpus" => vcpus} = Map.merge(@no_filters, params)

    if sort in Schemas.sorts() and order in ["asc", "desc"] and valid_search?(search) and
         status in [nil | Schemas.statuses()] and valid_vcpus?(vcpus) do
      {:ok,
       [
         sort_by: sort_field(sort),
         sort_order: String.to_existing_atom(order),
         search: search,
         status: status && {:==, String.to_existing_atom(status)},
         vcpus: vcpus && {:==, vcpus}
       ]}
    else
      {:error, :invalid_parameters}
    end
  end

  defp valid_search?(search), do: is_nil(search) or (is_binary(search) and String.length(search) in 1..200)
  defp valid_vcpus?(vcpus), do: is_nil(vcpus) or (is_integer(vcpus) and vcpus > 0)

  defp period(params) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    with {:ok, finish} <- datetime(Map.get(params, "end", now)),
         {:ok, start} <- datetime(Map.get(params, "start", DateTime.add(finish, -30, :day))),
         duration when duration > 0 and duration <= @max_range_seconds <- DateTime.diff(finish, start),
         true <- DateTime.compare(finish, now) != :gt do
      {:ok, {start, finish}}
    else
      _ -> {:error, :invalid_parameters}
    end
  end

  defp datetime(%DateTime{} = value), do: {:ok, value}

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, value, _} -> {:ok, DateTime.truncate(value, :second)}
      _ -> {:error, :invalid_parameters}
    end
  end

  defp datetime(_), do: {:error, :invalid_parameters}

  defp duration(summary) do
    %{
      count: summary.count,
      avg_ms: summary.avg,
      p50_ms: summary.p50,
      p90_ms: summary.p90,
      p99_ms: summary.p99,
      trend_avg: summary.trend_avg,
      trend_p50: summary.trend_p50,
      trend_p90: summary.trend_p90,
      trend_p99: summary.trend_p99,
      points:
        points(
          summary.dates,
          &%{
            avg_ms: Enum.at(summary.avg_values, &1),
            p50_ms: Enum.at(summary.p50_values, &1),
            p90_ms: Enum.at(summary.p90_values, &1),
            p99_ms: Enum.at(summary.p99_values, &1)
          }
        )
    }
  end

  # Hourly buckets are dated by a DateTime and daily ones by a Date.
  defp points(dates, fields) do
    dates
    |> Enum.with_index()
    |> Enum.map(fn {date, index} -> Map.put(fields.(index), :at, iso(date)) end)
  end

  defp iso(%Date{} = date), do: date |> DateTime.new!(~T[00:00:00], "Etc/UTC") |> iso()
  defp iso(%DateTime{} = value), do: value |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc -> String.replace(acc, "%{#{key}}", to_string(value)) end)
    end)
    |> Enum.map_join(", ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  defp metadata(page, size, count) do
    %{
      current_page: page,
      page_size: size,
      total_count: count,
      total_pages: ceil(count / size),
      has_next_page: page * size < count,
      has_previous_page: page > 1
    }
  end
end
