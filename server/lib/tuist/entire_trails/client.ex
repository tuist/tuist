defmodule Tuist.EntireTrails.Client do
  @moduledoc """
  Entire's commit Checks and Trail Findings APIs.
  Authentication and regional routing use the shared Entire plugin client.
  """

  alias Tuist.Entire.Client, as: Entire

  require Logger

  def trails(installation, repository) do
    list(installation, repository, path(repository) <> "/trails", params: [{"status", "open,draft"}])
  end

  def trail(installation, repository, number) do
    request(:get, installation, repository, trail_path(repository, number))
  end

  def publish(installation, repository, number, branch, summary) do
    attempt = "tuist-#{summary.id}-#{DateTime.to_unix(summary.reported_at, :microsecond)}"
    key = "tuist-insights-#{summary.connection_id}"
    reviews = trail_path(repository, number) <> "/reviews"

    state = %{
      key: key,
      name: "Tuist insights",
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
    with {:ok, token} <-
           Entire.access_token(installation, repository.id, %{
             "contents" => "read",
             "checks" => "write",
             "findings" => "write"
           }) do
      Entire.region_request(method, repository, path, token, opts)
    end
  end

  defp path(repository), do: "/repos/" <> segment(repository.id)
  defp trail_path(repository, number), do: path(repository) <> "/trails/" <> segment(to_string(number))
  defp segment(value), do: URI.encode(value, &URI.char_unreserved?/1)
end
