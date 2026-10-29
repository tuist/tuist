defmodule Atlas.Integrations.GitHubEvents do
  @moduledoc """
  Verifies and handles incoming GitHub webhook events.
  """

  alias Atlas.Product.Workers.AnnounceReleaseOnIssues
  alias Atlas.Product.Workers.IngestGitHubEvent

  def verify_signature(raw_body, signature, webhook_secret)
      when is_binary(raw_body) and is_binary(signature) and is_binary(webhook_secret) do
    expected =
      "sha256=" <>
        (:crypto.mac(:hmac, :sha256, webhook_secret, raw_body) |> Base.encode16(case: :lower))

    if Plug.Crypto.secure_compare(expected, signature) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  def verify_signature(_raw_body, _signature, _webhook_secret), do: {:error, :invalid_signature}

  def handle_event(event_type, payload, opts \\ [])

  def handle_event(event_type, payload, opts)
      when event_type in ["pull_request", "issues"] and is_map(payload) and is_list(opts) do
    action = payload["action"]

    if action in ["opened", "closed"] do
      %{"event_type" => event_type, "payload" => relevant_payload(event_type, payload)}
      |> maybe_put_github_app_id(Keyword.get(opts, :github_app_id))
      |> IngestGitHubEvent.new(
        unique: [period: 3_600, fields: [:worker, :args], states: [:available, :scheduled, :executing, :retryable]]
      )
      |> Oban.insert()
    else
      :ignored
    end
  end

  def handle_event("release", payload, opts) when is_map(payload) and is_list(opts) do
    with "published" <- payload["action"],
         %{"tag_name" => tag, "html_url" => release_url} = release
         when is_binary(tag) and is_binary(release_url) <- payload["release"],
         %{"name" => repo, "owner" => %{"login" => owner}}
         when is_binary(repo) and is_binary(owner) <- payload["repository"] do
      %{
        "owner" => owner,
        "repo" => repo,
        "tag" => tag,
        "release_url" => release_url,
        "release_body" => release["body"] || ""
      }
      |> maybe_put_github_app_id(Keyword.get(opts, :github_app_id))
      |> AnnounceReleaseOnIssues.new(
        unique: [
          period: :infinity,
          fields: [:worker, :args],
          keys: [:owner, :repo, :tag],
          states: [:available, :scheduled, :executing, :retryable, :completed]
        ]
      )
      |> Oban.insert()
    else
      _ -> :ignored
    end
  end

  def handle_event(_event_type, _payload, _opts), do: :ignored

  defp maybe_put_github_app_id(args, github_app_id) when is_binary(github_app_id),
    do: Map.put(args, "github_app_id", github_app_id)

  defp maybe_put_github_app_id(args, _github_app_id), do: args

  defp relevant_payload("pull_request", payload) do
    Map.take(payload, ["action", "installation", "repository", "pull_request"])
  end

  defp relevant_payload("issues", payload) do
    Map.take(payload, ["action", "installation", "repository", "issue"])
  end
end
