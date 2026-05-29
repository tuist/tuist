defmodule TuistWeb.OpsDatabaseLive do
  @moduledoc """
  Database inspection page under `/ops/db`. Replaces the pgweb instance
  the RFC originally specified — the same operator workflow (cluster
  stats, table sizes, index health, live activity, ad-hoc SQL) but
  running inside the Tuist server's authenticated `/ops` pipeline so
  every action carries the operator's identity through to logs and
  audit.

  All queries are read-only by construction: stats use
  `EctoPSQLExtras` directly; the SQL editor passes through
  `Tuist.Ops.Database.execute/2`, which gates the statement on a
  SELECT/WITH/EXPLAIN/SHOW grammar AND wraps execution in a `BEGIN
  READ ONLY` transaction.

  Writes still flow through `kubectl cnpg psql` with the cluster's
  superuser role — that path stays as the break-glass channel.
  """
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Ops.Database

  @sections ~w(overview tables indexes activity replication backups query)
  @page_size 20

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:head_title, "Database · Tuist Ops")
     |> assign(:section, "overview")
     |> assign(:query, "")
     |> assign(:query_result, nil)
     |> assign(:query_error, nil)
     |> assign(:page, 1)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    section = validate_section(params["section"])

    {:noreply,
     socket
     |> assign(:section, section)
     |> assign(:page, parse_page(params["page"]))
     |> load_for_section(section)}
  end

  @impl true
  def handle_event("run_query", %{"query" => sql}, socket) do
    case Database.execute(sql) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:query, sql)
         |> assign(:query_result, result)
         |> assign(:query_error, nil)
         # Fresh query → drop any stale ?page from a previous run.
         |> push_patch(to: ~p"/ops/db?section=query")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:query, sql)
         |> assign(:query_result, nil)
         |> assign(:query_error, to_string(reason))}
    end
  end

  def handle_event("export", %{"format" => format}, socket) do
    case socket.assigns.query_result do
      nil ->
        {:noreply, socket}

      result ->
        payload = export_payload(result, format)
        filename = "tuist-query-#{System.system_time(:second)}.csv"

        {:noreply,
         push_event(socket, "ops-db-export", %{
           format: format,
           payload: payload,
           filename: filename
         })}
    end
  end

  defp export_payload(result, "markdown"), do: Database.to_markdown(result)
  defp export_payload(result, "json"), do: Database.to_json(result)
  defp export_payload(result, "csv"), do: Database.to_csv(result)
  defp export_payload(result, "download-csv"), do: Database.to_csv(result)

  defp validate_section(s) when s in @sections, do: s
  defp validate_section(_), do: "overview"

  defp parse_page(nil), do: 1

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {p, _} when p > 0 -> p
      _ -> 1
    end
  end

  # Render a SQL result cell. Match the look of a SQL UI (Supabase /
  # pgweb / DBeaver): no quotes around strings and no decorators around
  # dates. `nil` is rendered as the literal NULL with a `data-null`
  # attribute on the cell container so CSS can mute the color.
  def format_cell(nil), do: "NULL"

  def format_cell(v) when is_binary(v) do
    cond do
      # Valid UTF-8 → render as-is.
      String.valid?(v) ->
        v

      # 16-byte non-UTF-8 binaries are almost always Postgres UUIDs
      # (uuidv4 / uuidv7 / etc — Postgrex hands them through as the raw
      # bytea). Format canonically so the `id` column doesn't render
      # as binary garbage.
      byte_size(v) == 16 ->
        case Ecto.UUID.cast(v) do
          {:ok, uuid} -> uuid
          :error -> hex_blob(v)
        end

      # Any other non-printable bytea (bytes, encrypted blobs, etc.)
      # gets the psql `\x...` hex form so the operator at least sees
      # the size + content.
      true ->
        hex_blob(v)
    end
  end

  def format_cell(v) when is_number(v) or is_boolean(v), do: to_string(v)
  def format_cell(%NaiveDateTime{} = v), do: NaiveDateTime.to_string(v)
  def format_cell(%DateTime{} = v), do: DateTime.to_string(v)
  def format_cell(%Date{} = v), do: Date.to_string(v)
  def format_cell(%Time{} = v), do: Time.to_string(v)
  # Composite / unknown types still need to render *somewhere*. Use
  # inspect/1 so jsonb maps and arrays at least serialize legibly
  # rather than crashing the cell.
  def format_cell(v), do: inspect(v)

  defp hex_blob(bin), do: "\\x" <> Base.encode16(bin, case: :lower)

  @doc "The current page's slice of the result rows."
  def displayed_rows(nil, _), do: []

  def displayed_rows(%{rows: rows}, page) do
    Enum.slice(rows, (page - 1) * @page_size, @page_size)
  end

  @doc "Total page count for the result-set pager (1 when empty)."
  def total_pages(nil), do: 1

  def total_pages(%{rows: rows}) do
    rows |> length() |> Kernel./(@page_size) |> Float.ceil() |> trunc() |> max(1)
  end

  @doc "Page size — exposed so the template can render the page meta."
  def page_size, do: @page_size

  def page_patch(page), do: "/ops/db?section=query&page=#{page}"

  @doc "Format `duration_us` (microseconds) as a human-readable string."
  def format_duration(us) when is_integer(us) and us < 1_000, do: "#{us}µs"
  def format_duration(us) when is_integer(us) and us < 1_000_000, do: "#{Float.round(us / 1_000, 1)}ms"
  def format_duration(us) when is_integer(us), do: "#{Float.round(us / 1_000_000, 2)}s"
  def format_duration(_), do: "—"

  @doc """
  Human-readable summary of when the last WAL was archived. Used in
  the Overview and Backups tabs as a single-glance "is the backup
  pipeline alive" indicator.
  """
  def archive_freshness(%{"last_archived_time" => nil}), do: dgettext("dashboard", "Not configured")

  def archive_freshness(%{"last_archived_time" => time}) do
    seconds = max(DateTime.diff(DateTime.utc_now(), time, :second), 0)
    relative_time(seconds) <> " ago"
  end

  def archive_freshness(_), do: "—"

  @doc """
  Subtitle for the Base backups empty state. Distinguishes "the page
  can't see the cluster" (dev / CNPG not provisioned, or the Kubernetes
  read was denied) from "the cluster has no backups yet", so an operator
  isn't misled into thinking backups are missing when it's really an
  access gap.
  """
  def base_backups_empty_subtitle(:not_configured),
    do:
      dgettext(
        "dashboard",
        "No CNPG cluster wired to this server (dev, or Postgres still on the external provider). Base backups appear once the server runs against the in-cluster cluster."
      )

  def base_backups_empty_subtitle(:unavailable),
    do:
      dgettext(
        "dashboard",
        "Could not read the cluster's Backup resources from the Kubernetes API — check the server ServiceAccount's RBAC on postgresql.cnpg.io."
      )

  def base_backups_empty_subtitle(_), do: dgettext("dashboard", "The cluster has not produced any base backups yet.")

  defp relative_time(s) when s < 60, do: "#{s}s"
  defp relative_time(s) when s < 3600, do: "#{div(s, 60)}m"
  defp relative_time(s) when s < 86_400, do: "#{div(s, 3600)}h"
  defp relative_time(s), do: "#{div(s, 86_400)}d"

  defp load_for_section(socket, "overview") do
    socket
    |> assign(:cluster_info, Database.cluster_info())
    |> assign(:archiver, Database.archiver_status())
  end

  defp load_for_section(socket, "tables") do
    assign(socket, :table_overviews, Database.list_table_overviews())
  end

  defp load_for_section(socket, "replication") do
    assign(socket, :replication, Database.replication())
  end

  defp load_for_section(socket, "backups") do
    {base_backups, base_backups_status} =
      case Database.list_base_backups() do
        {:ok, backups} -> {backups, :ok}
        {:error, reason} -> {[], reason}
      end

    socket
    |> assign(:archiver, Database.archiver_status())
    |> assign(:archive_settings, Database.archive_settings())
    |> assign(:base_backups, base_backups)
    |> assign(:base_backups_status, base_backups_status)
  end

  defp load_for_section(socket, "indexes") do
    socket
    |> assign(:unused_indexes, Database.unused_indexes())
    |> assign(:duplicate_indexes, Database.duplicate_indexes())
  end

  defp load_for_section(socket, "activity") do
    socket
    |> assign(:long_running_queries, Database.long_running_queries())
    |> assign(:locks, Database.locks())
  end

  defp load_for_section(socket, "query"), do: socket
end
