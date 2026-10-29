defmodule Atlas.Product.GitHubIngestion do
  @moduledoc false

  alias Atlas.Integrations
  alias Atlas.Product

  def ingest(event_type, payload, opts \\ []) when is_binary(event_type) and is_map(payload) and is_list(opts) do
    with {:ok, owner, repository_name} <- repository_identity(payload),
         {:ok, repository} <- get_repository(Keyword.get(opts, :github_app_id), owner, repository_name),
         {:ok, attrs} <- trace_attrs(event_type, payload, repository) do
      Product.record_trace(attrs)
    else
      :ignored -> :ignored
      {:error, :github_repository_not_configured} -> :ignored
      {:error, _reason} = error -> error
    end
  end

  defp get_repository(github_app_id, owner, repository_name) when is_binary(github_app_id),
    do: Integrations.get_github_repository(github_app_id, owner, repository_name)

  defp get_repository(_github_app_id, owner, repository_name),
    do: Integrations.get_github_repository(owner, repository_name)

  defp repository_identity(%{"repository" => %{"name" => name, "owner" => %{"login" => owner}}})
       when is_binary(name) and is_binary(owner), do: {:ok, owner, name}

  defp repository_identity(_payload), do: {:error, :invalid_github_repository}

  defp trace_attrs("pull_request", %{"action" => action, "pull_request" => pull_request} = payload, repository)
       when action in ["opened", "closed"] do
    kind = pull_request_kind(action, pull_request)

    attrs_for_item(kind, pull_request, payload, repository, "pull_request")
  end

  defp trace_attrs("issues", %{"action" => action, "issue" => issue} = payload, repository)
       when action in ["opened", "closed"] do
    attrs_for_item("issue_#{action}", issue, payload, repository, "issue")
  end

  defp trace_attrs(_event_type, _payload, _repository), do: :ignored

  defp attrs_for_item(kind, item, payload, repository, item_type) do
    with number when is_integer(number) <- item["number"],
         id when is_integer(id) <- item["id"],
         title when is_binary(title) <- item["title"],
         url when is_binary(url) <- item["html_url"],
         {:ok, occurred_at} <- occurred_at(kind, item) do
      {:ok,
       %{
         provider: "github",
         kind: kind,
         external_id: "#{item_type}:#{id}:#{kind}",
         github_repository_id: repository.id,
         repository_full_name: get_in(payload, ["repository", "full_name"]) || "#{repository.owner}/#{repository.repo}",
         number: number,
         title: title,
         url: url,
         author_login: get_in(item, ["user", "login"]),
         occurred_at: occurred_at,
         labels: labels(item),
         sensitivity: "internal"
       }}
    else
      _invalid -> {:error, :invalid_github_event}
    end
  end

  defp pull_request_kind("opened", _pull_request), do: "pull_request_opened"
  defp pull_request_kind("closed", %{"merged" => true}), do: "pull_request_merged"
  defp pull_request_kind("closed", _pull_request), do: "pull_request_closed"

  defp occurred_at("pull_request_merged", item), do: parse_datetime(item["merged_at"] || item["closed_at"])
  defp occurred_at("pull_request_closed", item), do: parse_datetime(item["closed_at"])
  defp occurred_at("issue_closed", item), do: parse_datetime(item["closed_at"])
  defp occurred_at(_kind, item), do: parse_datetime(item["created_at"])

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, DateTime.truncate(datetime, :second)}
      {:error, _reason} -> {:error, :invalid_github_timestamp}
    end
  end

  defp parse_datetime(_value), do: {:error, :invalid_github_timestamp}

  defp labels(%{"labels" => labels}) when is_list(labels) do
    labels
    |> Enum.flat_map(fn
      %{"name" => name} when is_binary(name) -> [name]
      _label -> []
    end)
    |> Enum.uniq()
  end

  defp labels(_item), do: []
end
