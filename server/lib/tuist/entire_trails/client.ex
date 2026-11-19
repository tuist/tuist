defmodule Tuist.EntireTrails.Client do
  @moduledoc """
  Entire's commit Checks, Trail Findings, and Trail discussions APIs.
  Authentication and regional routing use the shared Entire plugin client.
  """

  alias Tuist.Entire.Client, as: Entire

  require Logger

  @checks %{"contents" => "read", "checks" => "write", "findings" => "write"}
  # Comments use their own token, so installations that have not granted
  # discussions keep receiving checks and findings.
  @discussions %{"contents" => "read", "discussions" => "write"}

  def trails(installation, repository) do
    list(installation, repository, path(repository) <> "/trails", params: [{"status", "open,draft"}])
  end

  def trail(installation, repository, number) do
    request(:get, installation, repository, trail_path(repository, number))
  end

  # Entire shows a suite's key as its label on the Trail, and customers enter it
  # to require the check, so it is the project's handle. A project has at most
  # one connection, which keeps it unique among Tuist's suites on a commit.
  def publish(installation, repository, number, %{branch: branch, key: key, details_url: details_url}, summary) do
    attempt = "tuist-#{summary.id}-#{DateTime.to_unix(summary.reported_at, :microsecond)}"
    reviews = trail_path(repository, number) <> "/reviews"

    state = %{
      key: key,
      name: "Tuist insights",
      details_url: details_url,
      external_id: attempt,
      status: "completed",
      conclusion: "neutral",
      external_updated_at: DateTime.to_iso8601(summary.reported_at)
    }

    # These are uploaded observations, not an executor's final CI verdict.
    with {:ok, _} <-
           request(
             :post,
             installation,
             repository,
             path(repository) <> "/commits/#{segment(summary.head_sha)}/check-runs",
             json: %{
               branch: branch,
               check_suite: state,
               check_runs: [
                 Map.merge(state, %{key: "report", output: %{title: "Tuist insights", summary: summary.report_body}})
               ]
             }
           ),
         {:ok, %{"review_id" => review_id}} <-
           request(:post, installation, repository, reviews,
             headers: [{"idempotency-key", attempt <> "-review"}],
             json: %{head_sha: summary.head_sha}
           ),
         {:ok, %{"results" => results}} <-
           request(:post, installation, repository, reviews <> "/#{segment(review_id)}/comments",
             headers: [{"idempotency-key", attempt <> "-publish"}],
             json: %{summary: summary.report_body, comments: summary.findings}
           ),
         :ok <- resolve_previous(installation, repository, reviews, summary, review_id) do
      {:ok, %{review_id: review_id, finding_ids: Enum.map(results, & &1["comment"]["id"])}}
    end
  end

  defp resolve_previous(installation, repository, reviews, summary, review_id) do
    if summary.review_id && summary.review_id != review_id do
      Enum.reduce_while(summary.finding_ids, :ok, fn id, :ok ->
        case request(
               :patch,
               installation,
               repository,
               reviews <> "/#{segment(summary.review_id)}/comments/#{segment(id)}",
               json: %{status: "resolved", status_reason: "Superseded by an updated Tuist insights report."}
             ) do
          {:ok, _} -> {:cont, :ok}
          {:error, _} = error -> {:halt, error}
        end
      end)
    else
      :ok
    end
  end

  # Entire has no idempotency key for discussions. A comment whose create
  # response was lost is found again by its marker and author.
  def find_comment(installation, repository, number, marker) do
    base = trail_path(repository, number) <> "/discussions"

    with {:ok, discussions} <- list(installation, repository, base, permissions: @discussions) do
      discussions
      |> Enum.filter(&owned?(&1["created_by_identity"], installation))
      |> Enum.reduce_while({:ok, nil}, fn discussion, {:ok, nil} ->
        case comment_message(installation, repository, base <> "/" <> segment(discussion["id"]), marker) do
          {:ok, nil} -> {:cont, {:ok, nil}}
          {:ok, message} -> {:halt, {:ok, %{discussion_id: discussion["id"], message_id: message["id"]}}}
          {:error, _} = error -> {:halt, error}
        end
      end)
    end
  end

  defp comment_message(installation, repository, path, marker) do
    with {:ok, %{"messages" => messages}} <- request(:get, installation, repository, path, permissions: @discussions) do
      {:ok,
       Enum.find(
         messages || [],
         &(owned?(&1["identity"], installation) and String.contains?(&1["body"] || "", marker))
       )}
    end
  end

  def create_comment(installation, repository, number, title, body) do
    case request(:post, installation, repository, trail_path(repository, number) <> "/discussions",
           permissions: @discussions,
           json: %{title: title, body: body}
         ) do
      {:ok, %{"discussion" => %{"id" => discussion_id}, "message" => %{"id" => message_id}}} ->
        {:ok, %{discussion_id: discussion_id, message_id: message_id}}

      {:error, _} = error ->
        error
    end
  end

  def update_comment(installation, repository, number, %{discussion_id: discussion_id, message_id: message_id}, body) do
    request(
      :patch,
      installation,
      repository,
      trail_path(repository, number) <> "/discussions/#{segment(discussion_id)}/messages/#{segment(message_id)}",
      permissions: @discussions,
      json: %{body: body}
    )
  end

  defp owned?(%{"kind" => "automation", "automation" => %{"installation_id" => remote_id}}, installation),
    do: remote_id == installation.remote_id

  defp owned?(_, _), do: false

  defp list(installation, repository, path, opts, items \\ []) do
    with {:ok, body} <- request(:get, installation, repository, path, opts) do
      if is_nil(body["items"]) do
        Logger.warning("Entire Trail discovery response missing items repository_id=#{repository.id}")
      end

      items = items ++ (body["items"] || [])

      case body["next_cursor"] do
        cursor when is_binary(cursor) and cursor != "" ->
          opts = Keyword.update(opts, :params, [{"cursor", cursor}], &List.keystore(&1, "cursor", 0, {"cursor", cursor}))
          list(installation, repository, path, opts, items)

        _ ->
          {:ok, items}
      end
    end
  end

  defp request(method, installation, repository, path, opts \\ []) do
    {permissions, opts} = Keyword.pop(opts, :permissions, @checks)

    with {:ok, token} <- Entire.access_token(installation, repository.id, permissions) do
      Entire.region_request(method, repository, path, token, opts)
    end
  end

  defp path(repository), do: "/repos/" <> segment(repository.id)
  defp trail_path(repository, number), do: path(repository) <> "/trails/" <> segment(to_string(number))
  defp segment(value), do: URI.encode(value, &URI.char_unreserved?/1)
end
