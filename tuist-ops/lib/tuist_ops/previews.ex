defmodule TuistOps.Previews do
  @moduledoc """
  Slack-facing control plane for preview environments.
  """

  alias TuistOps.Previews.GitHubActionsClient
  alias TuistOps.Previews.Request
  alias TuistOps.Previews.SlackBlocks
  alias TuistOps.JIT.SlackClient
  alias TuistOps.Repo

  require Logger

  @default_ttl_seconds 24 * 60 * 60
  @max_ttl_seconds 7 * 24 * 60 * 60

  def request_create(attrs) when is_map(attrs) do
    ttl = attrs |> Map.get(:ttl_seconds, @default_ttl_seconds) |> clamp_ttl()
    slug = Map.fetch!(attrs, :slug)

    attrs =
      attrs
      |> Map.put(:action, "create")
      |> Map.put(:status, "requested")
      |> Map.put(:ttl_seconds, ttl)
      |> Map.put(:host, "#{slug}.preview.tuist.dev")
      |> Map.put(:namespace, "preview-ondemand-#{slug}")
      |> Map.put(:release, "ondemand-#{slug}")
      |> Map.put(:expires_at, DateTime.add(DateTime.utc_now(), ttl, :second))

    with {:ok, request} <- attrs |> Request.create_changeset() |> Repo.insert(),
         {:ok, ts} <-
           SlackClient.post_message(
             request.slack_channel_id,
             SlackBlocks.provisioning(request),
             fallback_text: "Preview requested"
           ),
         {:ok, workflow} <- dispatch_create(request),
         {:ok, request} <-
           request
           |> Request.transition_changeset(%{
             status: "provisioning",
             slack_message_ts: ts,
             workflow_id: workflow.workflow_id,
             workflow_ref: workflow.workflow_ref
           })
           |> Repo.update() do
      {:ok, request}
    else
      {:error, reason} ->
        Logger.warning("preview: create request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def request_delete(attrs) when is_map(attrs) do
    slug = Map.fetch!(attrs, :slug)

    attrs =
      attrs
      |> Map.put(:action, "delete")
      |> Map.put(:status, "requested")
      |> Map.put(:host, "#{slug}.preview.tuist.dev")
      |> Map.put(:namespace, "preview-ondemand-#{slug}")
      |> Map.put(:release, "ondemand-#{slug}")

    with {:ok, request} <- attrs |> Request.create_changeset() |> Repo.insert(),
         {:ok, ts} <-
           SlackClient.post_message(
             request.slack_channel_id,
             SlackBlocks.deleting(request),
             fallback_text: "Preview deletion requested"
           ),
         {:ok, workflow} <- dispatch_delete(request),
         {:ok, request} <-
           request
           |> Request.transition_changeset(%{
             status: "deleting",
             slack_message_ts: ts,
             workflow_id: workflow.workflow_id,
             workflow_ref: workflow.workflow_ref
           })
           |> Repo.update() do
      {:ok, request}
    else
      {:error, reason} ->
        Logger.warning("preview: delete request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp dispatch_create(%Request{} = request) do
    inputs =
      %{
        slug: request.slug,
        ttl_hours: Integer.to_string(ceil_hours(request.ttl_seconds)),
        requester_email: request.requester_email,
        requester_slack_id: request.requester_slack_id,
        reason: request.reason
      }
      |> maybe_put_ref(request)

    GitHubActionsClient.dispatch("create", inputs)
  end

  defp dispatch_delete(%Request{} = request) do
    GitHubActionsClient.dispatch("delete", %{
      slug: request.slug,
      requester_email: request.requester_email,
      requester_slack_id: request.requester_slack_id,
      reason: request.reason
    })
  end

  defp maybe_put_ref(inputs, %Request{ref_kind: "pr", ref_value: pr}) when is_binary(pr) do
    Map.put(inputs, :pr_number, pr)
  end

  defp maybe_put_ref(inputs, %Request{ref_kind: "sha", ref_value: sha}) when is_binary(sha) do
    Map.put(inputs, :commit_sha, sha)
  end

  defp maybe_put_ref(inputs, _request), do: inputs

  defp ceil_hours(seconds), do: div(seconds + 3599, 3600)

  defp clamp_ttl(ttl) when is_integer(ttl) and ttl > 0 do
    min(ttl, @max_ttl_seconds)
  end

  defp clamp_ttl(_), do: @default_ttl_seconds

  def default_ttl_seconds, do: @default_ttl_seconds
  def max_ttl_seconds, do: @max_ttl_seconds
end
