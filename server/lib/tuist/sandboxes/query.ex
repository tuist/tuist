defmodule Tuist.Sandboxes.Query do
  @moduledoc """
  Account-scoped public sandbox data and lifecycle actions shared by the
  HTTP API, MCP tools and the CLI, so the three return the same shapes and
  errors. Shapes are in `Tuist.Sandboxes.Schemas`.
  """
  alias Tuist.Accounts.Account
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Analytics
  alias Tuist.Sandboxes.Concurrency
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.Schemas

  @max_range_seconds 90 * 86_400
  @no_filters %{"search" => nil, "status" => nil, "vcpus" => nil}
  @create_fields ~w(platform template vcpus memory_mb workspace_gb)

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
  def run(:create, account, params) do
    attrs = for {key, value} <- params, key in @create_fields, into: %{}, do: {String.to_existing_atom(key), value}

    with {:ok, created} <- Sandboxes.create_sandbox(account, attrs), do: {:ok, sandbox(created)}
  end

  def run(:show, account, params) do
    with {:ok, found} <- find(account, params), do: {:ok, sandbox(found)}
  end

  def run(:pause, account, params), do: transition(account, params, &Sandboxes.pause/1)
  def run(:resume, account, params), do: transition(account, params, &Sandboxes.resume/1)

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
           in_use: %{
             vcpus: in_use.vcpus,
             memory_gb: Float.round(in_use.memory_mb / 1024, 1)
           },
           points:
             points(
               concurrency.dates,
               &%{
                 vcpus: Enum.at(concurrency.vcpus, &1),
                 memory_gb: Enum.at(concurrency.memory_gb, &1) * 1.0
               }
             )
         }
       }}
    end
  end

  @doc """
  The HTTP status and message for an error `run/3` returned.
  """
  def error({:invalid_state, state}), do: {:conflict, "The sandbox is #{state}."}
  def error(:not_found), do: {:not_found, "Sandbox not found."}

  def error({:invalid_cwd, cwd}),
    do: {:bad_request, "The working directory #{cwd} does not exist in the sandbox or is not a directory."}

  def error(:invalid_parameters),
    do:
      {:bad_request,
       "Invalid identifier, pagination, filter, sorting or time range. Use an ordered range of at most 90 days ending no later than now."}

  def error(:no_node), do: {:service_unavailable, "No sandbox node with the template ready is connected."}

  def error(:sandbox_concurrency_limit),
    do:
      {:too_many_requests,
       "The account has reached its sandbox CPU or memory limit. Pause a sandbox before starting more work."}

  def error(:sandbox_account_busy), do: {:conflict, "Another sandbox admission is in progress. Retry shortly."}
  def error(:busy), do: {:conflict, "An agent turn or another command is running in the sandbox."}

  def error(:invalid_command),
    do:
      {:bad_request,
       "Invalid command: it needs a non-empty command, string arguments, environment names of letters, digits and underscores, and stdin data of at most 256 KiB in base64."}

  def error(:stdin_not_attached), do: {:conflict, "The command was not started with stdin attached."}
  def error(:stdin_closed), do: {:conflict, "The command's stdin is closed."}

  def error(:stdin_offset_mismatch),
    do: {:conflict, "The write does not continue the command's stdin: its offset is not the number of bytes stdin holds."}

  def error(:locked), do: {:conflict, "Another operation on the sandbox is in progress."}
  def error(:no_capacity), do: {:service_unavailable, "No sandbox node has memory or disk left for this sandbox."}

  def error(:archive_store_unavailable),
    do:
      {:service_unavailable,
       "The storage that holds this sandbox's archive is not configured on this server, so the archive can't be reached."}

  def error(:not_connected), do: {:service_unavailable, "The sandbox's node is not connected."}
  def error(:node_disconnected), do: {:service_unavailable, "The sandbox's node disconnected during the operation."}
  def error(:timeout), do: {:gateway_timeout, "The sandbox's node did not answer in time."}

  def error(:snapshot_not_saved),
    do: {:service_unavailable, "The Orb paused, but its project snapshot could not be saved."}

  def error(%Ecto.Changeset{} = changeset), do: {:bad_request, changeset_message(changeset)}
  def error(reason) when is_binary(reason), do: {:bad_gateway, "The sandbox node rejected the operation: #{reason}"}
  def error(reason), do: {:internal_server_error, "Sandbox operation failed: #{inspect(reason)}"}

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
      :error_message,
      :inserted_at,
      :updated_at
    ])
    |> Map.put(:status, status(sandbox))
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
