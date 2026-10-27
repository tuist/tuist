defmodule Tuist.EntireTrails do
  @moduledoc """
  Publishes Tuist insights as one maintained discussion per project and Entire
  repository Trail. GitHub connections can coexist with these connections.
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
    case Repo.get(Connection, connection_id) do
      nil ->
        :ok

      connection ->
        connection = Repo.preload(connection, [:installation, project: :account])

        if connection.installation.active and enabled?(connection.project.account) do
          case sync_connection(connection) do
            {:error, :revoked} -> :ok
            result -> result
          end
        else
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
      Enum.reduce_while(trails, :ok, fn trail, :ok ->
        case sync_locked_trail(connection.id, repository, trail["number"]) do
          :ok -> {:cont, :ok}
          {:error, _} = error -> {:halt, error}
        end
      end)
    end
  end

  defp sync_locked_trail(connection_id, repository, number) do
    # A follow-up job can be queued during execution. Serialize comment writes
    # and commit each pointer separately, without locking across the full list.
    fn ->
      with %Connection{} = connection <- Repo.one(from c in Connection, where: c.id == ^connection_id, lock: "FOR UPDATE"),
           connection = Repo.preload(connection, [:installation, project: :account]),
           true <- connection.installation.active and enabled?(connection.project.account),
           :ok <- sync_trail(connection, repository, number) do
        :ok
      else
        {:error, reason} -> Repo.rollback(reason)
        _ -> :ok
      end
    end
    |> Repo.transaction(timeout: 60_000)
    |> case do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp sync_trail(connection, repository, number) do
    with {:ok, trail} <- Client.trail(connection.installation, repository, number),
         true <- trail["status"] in ["open", "draft"],
         sha when is_binary(sha) and sha != "" <- trail["head_sha"],
         body when is_binary(body) <- report(connection.project, sha),
         # Rendering can involve several queries. Do not publish an old head's
         # results if the Trail advanced or closed while the report was built.
         {:ok, current} <- Client.trail(connection.installation, repository, number),
         true <- current["head_sha"] == sha and current["status"] in ["open", "draft"] do
      summary = Repo.get_by(Summary, connection_id: connection.id, trail_id: trail["id"])

      case update_summary(connection, repository, number, summary, body) do
        {:ok, ids} ->
          %Summary{connection_id: connection.id, trail_id: trail["id"]}
          |> Ecto.Changeset.change(ids)
          |> Repo.insert!(
            on_conflict: {:replace, [:discussion_id, :message_id, :updated_at]},
            conflict_target: [:connection_id, :trail_id]
          )

          :ok

        {:error, _} = error ->
          error
      end
    else
      {:error, _} = error -> error
      _ -> :ok
    end
  end

  defp update_summary(connection, repository, number, nil, body) do
    marker = marker(connection.project)

    with {:ok, summary} <- Client.find_summary(connection.installation, repository, number, marker) do
      if summary do
        update_summary(connection, repository, number, summary, body)
      else
        Client.create_summary(connection.installation, repository, number, body)
      end
    end
  end

  defp update_summary(connection, repository, number, summary, body) do
    case Client.update_summary(connection.installation, repository, number, summary, body) do
      {:ok, _} -> {:ok, Map.take(summary, [:discussion_id, :message_id])}
      {:error, _} = error -> error
    end
  end

  defp report(project, sha) do
    base_url = Environment.app_url(path: "/#{project.account.name}/#{project.name}")

    body =
      VCS.get_run_report(%{
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

    if body do
      body = body <> "\n\n" <> marker(project)

      if String.length(body) <= 65_536 do
        body
      else
        "### Tuist insights for `#{sha}`\n\n[View the full report](#{base_url})\n\n" <> marker(project)
      end
    end
  end

  defp marker(project), do: "<!-- tuist-project:#{project.id} -->"
end
