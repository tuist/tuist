defmodule TuistOps.Previews do
  @moduledoc """
  Slack-facing control plane for preview environments.

  State model: one row per slug in the `previews` table. `/preview create`
  upserts into that row (rejecting if the preview is still in flight);
  `/preview delete` looks up the row by slug and transitions it. Failures
  flip the row to `failed`. The data is current state, not a request log
  — separate request/event history can land later if we want a full audit
  trail (see Marek's review of PR #11348 for the reasoning).
  """

  alias TuistOps.Previews.GitHubActionsClient
  alias TuistOps.Previews.Preview
  alias TuistOps.Previews.SlackBlocks
  alias TuistOps.JIT.SlackClient
  alias TuistOps.Repo

  require Logger

  @default_ttl_seconds 24 * 60 * 60
  @max_ttl_seconds 7 * 24 * 60 * 60

  def create(attrs) when is_map(attrs) do
    ttl = attrs |> Map.get(:ttl_seconds, @default_ttl_seconds) |> clamp_ttl()
    slug = Map.fetch!(attrs, :slug)

    attrs =
      attrs
      |> Map.put(:status, "creating")
      |> Map.put(:ttl_seconds, ttl)
      |> Map.put(:host, "#{slug}.preview.tuist.dev")
      |> Map.put(:namespace, "preview-ondemand-#{slug}")
      |> Map.put(:release, "ondemand-#{slug}")
      |> Map.put(:expires_at, DateTime.add(DateTime.utc_now(), ttl, :second))

    Repo.transaction(fn ->
      case Repo.get_by(Preview, slug: slug) do
        nil ->
          insert_new(attrs)

        %Preview{status: status} = existing ->
          if Preview.active_status?(status) do
            Repo.rollback(:already_exists)
          else
            reset_to_creating(existing, attrs)
          end
      end
    end)
    |> case do
      {:ok, {:ok, preview}} -> dispatch_create_after_insert(preview)
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def delete(attrs) when is_map(attrs) do
    slug = Map.fetch!(attrs, :slug)

    case Repo.get_by(Preview, slug: slug) do
      nil ->
        {:error, :not_found}

      %Preview{status: "deleted"} ->
        {:error, :not_found}

      %Preview{} = preview ->
        provision(
          preview,
          %{
            status: "deleting",
            slack_channel_id: Map.fetch!(attrs, :slack_channel_id),
            reason: Map.get(attrs, :reason, preview.reason)
          },
          "Preview deletion requested",
          &SlackBlocks.deleting/1,
          &dispatch_delete/1
        )
    end
  end

  defp insert_new(attrs) do
    attrs
    |> Preview.create_changeset()
    |> Repo.insert()
  end

  defp reset_to_creating(%Preview{} = existing, attrs) do
    existing
    |> Preview.transition_changeset(
      attrs
      |> Map.put(:status, "creating")
      |> Map.put(:failed_at, nil)
      |> Map.put(:failure_reason, nil)
      |> Map.put(:deleted_at, nil)
      |> Map.put(:slack_message_ts, nil)
      |> Map.put(:workflow_id, nil)
      |> Map.put(:workflow_ref, nil)
    )
    |> Repo.update()
  end

  defp dispatch_create_after_insert(%Preview{} = preview) do
    provision(
      preview,
      %{status: "creating"},
      "Preview requested",
      &SlackBlocks.provisioning/1,
      &dispatch_create/1
    )
  end

  # Posts the Slack status card, dispatches the workflow, and persists the
  # workflow ids on success. On failure the row is flipped to `failed`
  # (with the reason persisted) and the Slack card is replaced with the
  # failure variant so operators see what actually happened instead of a
  # stale "provisioning…" message.
  defp provision(%Preview{} = preview, base_attrs, fallback_text, render, dispatch) do
    with {:ok, ts} <-
           SlackClient.post_message(
             Map.get(base_attrs, :slack_channel_id, preview.slack_channel_id),
             render.(preview),
             fallback_text: fallback_text
           ),
         {:ok, workflow} <- dispatch.(preview),
         {:ok, preview} <-
           preview
           |> Preview.transition_changeset(
             Map.merge(base_attrs, %{
               slack_message_ts: ts,
               workflow_id: workflow.workflow_id,
               workflow_ref: workflow.workflow_ref
             })
           )
           |> Repo.update() do
      {:ok, preview}
    else
      {:error, reason} ->
        Logger.warning("preview: provision failed: #{inspect(reason)}")
        mark_failed(preview, reason)
        {:error, reason}
    end
  end

  defp mark_failed(%Preview{} = preview, reason) do
    failure_reason = reason |> inspect() |> String.slice(0, 500)

    {:ok, preview} =
      preview
      |> Preview.transition_changeset(%{
        status: "failed",
        failed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        failure_reason: failure_reason
      })
      |> Repo.update()

    case preview.slack_message_ts do
      ts when is_binary(ts) ->
        SlackClient.update_message(
          preview.slack_channel_id,
          ts,
          SlackBlocks.failed(preview, reason),
          fallback_text: "Preview request failed"
        )

      _ ->
        SlackClient.post_message(
          preview.slack_channel_id,
          SlackBlocks.failed(preview, reason),
          fallback_text: "Preview request failed"
        )
    end
  end

  defp dispatch_create(%Preview{} = preview) do
    inputs =
      %{
        slug: preview.slug,
        ttl_hours: Integer.to_string(ceil_hours(preview.ttl_seconds)),
        requester_email: preview.requester_email,
        requester_slack_id: preview.requester_slack_id,
        reason: preview.reason
      }
      |> maybe_put_ref(preview)

    GitHubActionsClient.dispatch("create", inputs)
  end

  defp dispatch_delete(%Preview{} = preview) do
    GitHubActionsClient.dispatch("delete", %{
      slug: preview.slug,
      requester_email: preview.requester_email,
      requester_slack_id: preview.requester_slack_id,
      reason: preview.reason
    })
  end

  defp maybe_put_ref(inputs, %Preview{ref_kind: "pr", ref_value: pr}) when is_binary(pr) do
    Map.put(inputs, :pr_number, pr)
  end

  defp maybe_put_ref(inputs, %Preview{ref_kind: "sha", ref_value: sha}) when is_binary(sha) do
    Map.put(inputs, :commit_sha, sha)
  end

  defp maybe_put_ref(inputs, _preview), do: inputs

  defp ceil_hours(seconds), do: div(seconds + 3599, 3600)

  defp clamp_ttl(ttl) when is_integer(ttl) and ttl > 0 do
    min(ttl, @max_ttl_seconds)
  end

  defp clamp_ttl(_), do: @default_ttl_seconds

  def default_ttl_seconds, do: @default_ttl_seconds
  def max_ttl_seconds, do: @max_ttl_seconds
end
