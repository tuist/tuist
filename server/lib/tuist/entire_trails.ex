defmodule Tuist.EntireTrails do
  @moduledoc """
  Publishes Tuist insights as commit checks and head-pinned Trail reviews.
  GitHub connections can coexist with these connections.
  """

  import Ecto.Query

  alias Tuist.Entire.Client, as: Entire
  alias Tuist.Entire.Installation
  alias Tuist.EntireTrails.Client
  alias Tuist.EntireTrails.Connection
  alias Tuist.EntireTrails.Summary
  alias Tuist.EntireTrails.Workers.ReportWorker
  alias Tuist.Environment
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.VCS

  require Logger

  def enabled?(account), do: Entire.configured?() and FunWithFlags.enabled?(:entire_trails, for: account)

  def installations(account) do
    Installation
    |> where([i], i.account_id == ^account.id and i.active)
    |> Repo.all()
  end

  def connections(account) do
    Connection
    |> join(:inner, [c], p in assoc(c, :project))
    |> where([_c, p], p.account_id == ^account.id)
    |> preload(:project)
    |> Repo.all()
  end

  def repositories(account) do
    account
    |> installations()
    |> Enum.reduce_while({:ok, []}, fn installation, {:ok, repositories} ->
      case Entire.repositories(installation) do
        {:ok, selected} ->
          entries = Enum.map(selected, &%{id: &1["id"], name: &1["full_name"], installation_id: installation.id})
          {:cont, {:ok, repositories ++ entries}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  def connect(account, attrs) do
    changeset = Connection.changeset(%Connection{}, Map.put(attrs, :repository_name, "pending"))

    with true <- enabled?(account),
         {:ok, connection} <- Ecto.Changeset.apply_action(changeset, :insert),
         %Project{} <- Repo.get_by(Project, id: connection.project_id, account_id: account.id),
         %Installation{} = installation <-
           Repo.get_by(Installation, id: connection.installation_id, account_id: account.id, active: true),
         {:ok, repository} <- Entire.repository(installation, connection.repository_id),
         {:ok, connection} <-
           %Connection{}
           |> Connection.changeset(Map.put(attrs, :repository_name, repository.name))
           |> Repo.insert() do
      enqueue_connection(connection)
      {:ok, connection}
    else
      {:error, _} = error -> error
      _ -> {:error, :not_found}
    end
  end

  def disconnect(account, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Connection{} = connection <-
           Connection
           |> join(:inner, [c], p in assoc(c, :project))
           |> where([c, p], c.id == ^id and p.account_id == ^account.id)
           |> Repo.one() do
      Repo.delete(connection)
    else
      _ -> {:error, :not_found}
    end
  end

  def enqueue(project_id) do
    Connection
    |> where([c], c.project_id == ^project_id)
    |> Repo.all()
    |> Enum.each(&enqueue_connection/1)
  end

  # Re-read authoritative Trail state rather than trusting event order. This
  # also covers Trails opened after their commit's insights were uploaded.
  def handle_delivery(%{
        "installation_id" => remote_id,
        "event" => %{"type" => type, "payload" => %{"repository" => %{"id" => repository_id}}}
      })
      when type in ["trail.opened", "trail.updated", "trail.reopened"] do
    Connection
    |> join(:inner, [c], i in assoc(c, :installation))
    |> where([c, i], i.remote_id == ^remote_id and c.repository_id == ^repository_id)
    |> Repo.all()
    |> Enum.each(&enqueue_connection/1)

    :ok
  end

  def handle_delivery(_), do: :ok

  def sync(connection_id) do
    Logger.info("Entire sync started connection_id=#{connection_id}")

    case Repo.get(Connection, connection_id) do
      nil ->
        Logger.info("Entire sync skipped connection_id=#{connection_id} reason=connection_missing")
        :ok

      connection ->
        connection = Repo.preload(connection, [:installation, project: :account])

        if connection.installation.active and enabled?(connection.project.account) do
          case sync_connection(connection) do
            {:error, :revoked} ->
              Logger.warning("Entire sync skipped connection_id=#{connection_id} reason=revoked")
              :ok

            result ->
              result
          end
        else
          Logger.info(
            "Entire sync skipped connection_id=#{connection_id} reason=disabled " <>
              "installation_active=#{connection.installation.active} configured=#{Entire.configured?()}"
          )

          :ok
        end
    end
  end

  defp enqueue_connection(connection) do
    delay = div(Environment.clickhouse_flush_interval_ms(), 1000) + 1
    %{connection_id: connection.id} |> ReportWorker.new(schedule_in: delay) |> Oban.insert()
  end

  defp sync_connection(connection) do
    with {:ok, repository} <- Entire.repository(connection.installation, connection.repository_id),
         {:ok, trails} <- Client.trails(connection.installation, repository) do
      Logger.info("Entire Trail discovery connection_id=#{connection.id} trail_count=#{length(trails)}")

      Enum.reduce_while(trails, :ok, fn trail, :ok ->
        case sync_locked_trail(connection.id, repository, trail["number"]) do
          :ok -> {:cont, :ok}
          {:error, _} = error -> {:halt, error}
        end
      end)
    end
  end

  defp sync_locked_trail(connection_id, repository, number) do
    # Commit the snapshot before contacting Entire, so a lost response or a
    # worker restart reuses exactly the same attempt and idempotency keys.
    with {:ok, summary} <- locked_trail(connection_id, &prepare_trail(&1, repository, number)),
         {:ok, summary} <- locked_trail(connection_id, &start_publication(&1, repository, number, summary)),
         {:ok, _} <- locked_trail(connection_id, &publish_trail(&1, repository, number, summary)) do
      :ok
    end
  end

  defp start_publication(_connection, _repository, _number, nil), do: nil

  defp start_publication(connection, repository, number, summary) do
    current = Repo.get!(Summary, summary.id)

    cond do
      current.reported_at != summary.reported_at or current.published_at == current.reported_at ->
        Logger.info(
          "Entire report skipped connection_id=#{connection.id} trail_number=#{number} reason=already_published_or_superseded"
        )

        nil

      current.publication_started ->
        current

      true ->
        with {:ok, trail} <- Client.trail(connection.installation, repository, number),
             true <- trail["head_sha"] == current.head_sha and trail["status"] in ["open", "draft"] do
          # Persist before any writes. Once started, this exact attempt must be
          # recovered even if the Trail head changes or has no new insights.
          current |> Ecto.Changeset.change(publication_started: true) |> Repo.update!()
        else
          {:error, _} = error ->
            error

          _ ->
            Logger.info(
              "Entire report skipped connection_id=#{connection.id} trail_number=#{number} reason=trail_changed"
            )

            nil
        end
    end
  end

  defp publish_trail(_connection, _repository, _number, nil), do: :ok

  defp publish_trail(connection, repository, number, summary) do
    current = Repo.get!(Summary, summary.id)

    with true <- current.reported_at == summary.reported_at and current.published_at != current.reported_at,
         {:ok, trail} <- Client.trail(connection.installation, repository, number),
         true <- trail["status"] in ["open", "draft"],
         {:ok, ids} <- Client.publish(connection.installation, repository, number, trail["branch"], current) do
      current
      |> Ecto.Changeset.change(Map.put(ids, :published_at, current.reported_at))
      |> Repo.update!()

      Logger.info("Entire report published connection_id=#{connection.id} trail_number=#{number}")
      :ok
    else
      {:error, _} = error ->
        error

      _ ->
        Logger.info(
          "Entire report skipped connection_id=#{connection.id} trail_number=#{number} reason=publication_no_longer_eligible"
        )

        :ok
    end
  end

  defp locked_trail(connection_id, fun) do
    Repo.transaction(
      fn ->
        with %Connection{} = connection <-
               Repo.one(from c in Connection, where: c.id == ^connection_id, lock: "FOR UPDATE"),
             connection = Repo.preload(connection, [:installation, project: :account]),
             true <- connection.installation.active and enabled?(connection.project.account) do
          case fun.(connection) do
            {:error, reason} -> Repo.rollback(reason)
            result -> result
          end
        else
          _ ->
            Logger.info("Entire sync skipped connection_id=#{connection_id} reason=connection_missing_or_disabled")
            nil
        end
      end,
      timeout: 60_000
    )
  end

  defp prepare_trail(connection, repository, number) do
    Logger.info("Entire report preparation started connection_id=#{connection.id} trail_number=#{number}")

    with {:ok, trail} <- Client.trail(connection.installation, repository, number),
         {:eligible_status, true} <- {:eligible_status, trail["status"] in ["open", "draft"]},
         {:head_sha, sha} when is_binary(sha) and sha != "" <- {:head_sha, trail["head_sha"]} do
      case Repo.get_by(Summary, connection_id: connection.id, trail_id: trail["id"]) do
        %{publication_started: true, published_at: published_at, reported_at: reported_at} = summary
        when published_at != reported_at ->
          # Do not replace an uncertain attempt, including after a head change.
          # The follow-up will render current insights after recovering its IDs.
          enqueue_connection(connection)
          summary

        summary ->
          prepare_report(connection, trail, summary)
      end
    else
      {:error, _} = error ->
        error

      {reason, _} ->
        Logger.info(
          "Entire report skipped connection_id=#{connection.id} trail_number=#{number} reason=invalid_#{reason}"
        )

        nil
    end
  end

  defp prepare_report(connection, trail, summary) do
    sha = trail["head_sha"]

    case report(connection.project, sha) do
      %{body: body, findings: findings} ->
        if match?(%{head_sha: ^sha, report_body: ^body, findings: ^findings}, summary) do
          summary
        else
          (summary || %Summary{connection_id: connection.id, trail_id: trail["id"]})
          |> Ecto.Changeset.change(
            head_sha: sha,
            report_body: body,
            findings: findings,
            reported_at: next_reported_at(summary),
            publication_started: false
          )
          |> Repo.insert_or_update!()
        end

      nil ->
        Logger.info(
          "Entire report skipped connection_id=#{connection.id} trail_number=#{trail["number"]} reason=no_insights"
        )

        nil
    end
  end

  defp next_reported_at(summary) do
    now = DateTime.from_unix!(System.system_time(:millisecond) * 1000, :microsecond)

    if summary && summary.reported_at && DateTime.compare(now, summary.reported_at) != :gt,
      do: DateTime.add(summary.reported_at, 1, :millisecond),
      else: now
  end

  defp report(project, sha) do
    base_url = Environment.app_url(path: "/#{project.account.name}/#{project.name}")

    report =
      VCS.get_run_report_sections(%{
        project: project,
        git_ref: nil,
        git_commit_sha: sha,
        git_remote_url_origin: nil,
        preview_url: fn %{preview: preview} -> base_url <> "/previews/#{preview.id}" end,
        preview_qr_code_url: fn %{preview: preview} -> base_url <> "/previews/#{preview.id}/qr-code.png" end,
        test_run_url: fn %{test_run: run} -> base_url <> "/tests/test-runs/#{run.id}" end,
        build_url: fn %{build: build} -> base_url <> "/builds/build-runs/#{build.id}" end,
        bundle_url: fn %{bundle: bundle} -> base_url <> "/bundles/#{bundle.id}" end
      })

    if report do
      fallback = "### Tuist insights for `#{sha}`\n\n[View the full report](#{base_url})"

      findings =
        [{"failed-tests", "medium", report.failed_tests}, {"flaky-tests", "low", report.flaky_tests}]
        |> Enum.reject(fn {_, _, body} -> is_nil(body) end)
        |> Enum.map(fn {id, severity, body} ->
          %{
            "client_id" => id,
            "body" => if(byte_size(body) <= 65_535, do: body, else: fallback),
            "severity" => severity,
            "location" => %{"granularity" => "whole_change"}
          }
        end)

      %{body: if(byte_size(report.summary) <= 65_535, do: report.summary, else: fallback), findings: findings}
    end
  end
end
