defmodule Tuist.Origin.Reports do
  @moduledoc "Publishes Tuist feedback to native Origin repositories."

  alias Tuist.Environment
  alias Tuist.Origin.Client
  alias Tuist.Origin.Installation
  alias Tuist.Projects.VCSConnection
  alias Tuist.Repo
  alias Tuist.VCS

  def post_comment(params, render) do
    project = Repo.preload(params.project, vcs_connection: :origin_app_installation)

    with %{provider: :origin, origin_app_installation: %Installation{suspended: false} = installation} = connection <-
           project.vcs_connection,
         true <- installation.account_id == project.account_id,
         number when is_integer(number) <- VCS.pull_request_number_from_git_ref(params.git_ref),
         {:ok, repository} <- repository(installation, connection),
         true <- matches_remote?(repository["fullName"], params.git_remote_url_origin),
         {:ok, pr} <- Client.get_pull_request(installation, repository["fullName"], number),
         {:ok, true} <- current_commit?(installation, repository["fullName"], pr, params.git_commit_sha),
         body when is_binary(body) <- render.(%{params | project: project, git_remote_url_origin: repository["webUrl"]}),
         {:ok, comments} <- Client.comments(installation, repository["fullName"], number) do
      marker = "<!-- tuist-project:#{project.id} -->"
      body = body <> "\n" <> marker
      app_id = Environment.origin_app_credentials().app_id

      existing =
        Enum.find(comments, fn comment ->
          get_in(comment, ["author", "app", "id"]) == app_id and
            String.ends_with?(comment["body"] || "", marker)
        end)

      result =
        if existing,
          do: Client.update_comment(installation, repository["fullName"], existing["id"], body),
          else: Client.create_comment(installation, repository["fullName"], number, body)

      case result do
        {:ok, _} -> :ok
        error -> error
      end
    else
      {:error, _} = error -> error
      _ -> :ok
    end
  end

  def repository(installation, connection) do
    with {:ok, repositories} <- Client.repositories(installation),
         %{} = repository <-
           Enum.find(repositories, &(&1["id"] == connection.origin_repository_id and is_nil(&1["mirror"]))),
         {:ok, _} <- refresh_handle(connection, repository["fullName"]) do
      {:ok, repository}
    else
      {:error, _} = error -> error
      _ -> {:error, :repository_not_accessible}
    end
  end

  defp refresh_handle(%{repository_full_handle: handle} = connection, handle), do: {:ok, connection}

  defp refresh_handle(connection, handle) do
    connection |> VCSConnection.changeset(%{repository_full_handle: handle}) |> Repo.update()
  end

  # Buildkite can check out either the head or Origin's synthetic merge ref.
  # Comparing against the current merge ref also rejects late force-push reports.
  def current_commit?(installation, repository, %{"state" => "open", "head" => %{"sha" => head}} = pr, sha)
      when is_binary(sha) and sha != "" do
    if sha == head do
      {:ok, true}
    else
      case Client.get_git_ref(installation, repository, "pull/#{pr["number"]}/merge") do
        {:ok, %{"object" => %{"sha" => ^sha}}} ->
          with {:ok, %{"parents" => parents}} <- Client.get_git_commit(installation, repository, sha) do
            {:ok, Enum.any?(parents, &(&1["sha"] == head))}
          end

        {:ok, _} ->
          {:ok, false}

        {:error, {:http, 404}} ->
          {:ok, false}

        error ->
          error
      end
    end
  end

  def current_commit?(_, _, _, _), do: {:ok, false}

  defp matches_remote?(handle, remote) when is_binary(remote) do
    case URI.parse(remote) do
      %URI{scheme: "https", host: "origin.cursor.com", port: 443, path: path} when is_binary(path) ->
        String.trim_trailing(path, ".git") in ["/git/" <> handle, "/" <> handle]

      _ ->
        false
    end
  end

  defp matches_remote?(_, _), do: false
end
