defmodule Tuist.Slack.Unfurl do
  @moduledoc """
  URL parsing and Block Kit attachment building for Slack link unfurling.
  """

  alias Tuist.Builds.Build
  alias Tuist.Utilities.DateFormatter

  def parse_url(url) do
    uri = URI.parse(url)

    case path_segments(uri.path) do
      [account_handle, project_handle, "builds", "build-runs", id] ->
        {:ok,
         {:build_run,
          %{
            account_handle: account_handle,
            project_handle: project_handle,
            build_run_id: id
          }}}

      _ ->
        :error
    end
  end

  defp path_segments(nil), do: []

  defp path_segments(path) do
    path
    |> String.split("/")
    |> Enum.reject(&(&1 == ""))
  end

  def build_build_run_blocks(%Build{} = build, url) do
    status_emoji = if build.status == "success", do: ":white_check_mark:", else: ":x:"
    scheme_label = if build.scheme == "", do: "Build", else: build.scheme

    fields = build_fields(build)
    tags_block = build_tags_block(build)

    blocks =
      [
        %{
          type: "section",
          text: %{
            type: "mrkdwn",
            text: "#{status_emoji} *<#{url}|#{scheme_label}>* #{String.capitalize(build.status)}"
          }
        },
        %{
          type: "section",
          fields: fields
        }
      ] ++ tags_block

    %{blocks: blocks}
  end

  defp build_fields(build) do
    []
    |> maybe_add_field(build.duration && build.duration > 0, fn ->
      mrkdwn_field("Duration", DateFormatter.format_duration_from_milliseconds(build.duration))
    end)
    |> maybe_add_field(build.git_branch != "", fn ->
      mrkdwn_field("Branch", build.git_branch)
    end)
    |> maybe_add_field(build.git_commit_sha != "", fn ->
      mrkdwn_field("Commit", format_commit(build))
    end)
    |> Kernel.++([mrkdwn_field("Environment", format_environment(build))])
    |> maybe_add_field(build.category != "", fn ->
      mrkdwn_field("Category", String.capitalize(build.category))
    end)
    |> maybe_add_field(build.configuration != "", fn ->
      mrkdwn_field("Configuration", build.configuration)
    end)
    |> maybe_add_field(build.xcode_version != "", fn ->
      mrkdwn_field("Xcode", build.xcode_version)
    end)
    |> maybe_add_field(build.macos_version != "", fn ->
      mrkdwn_field("macOS", build.macos_version)
    end)
    |> maybe_add_field(build.model_identifier != "", fn ->
      mrkdwn_field("Machine", build.model_identifier)
    end)
    |> maybe_add_field(build.cacheable_tasks_count > 0, fn ->
      mrkdwn_field("Cache", format_cache_hit_rate(build))
    end)
  end

  defp maybe_add_field(fields, condition, field_fn) do
    if condition, do: fields ++ [field_fn.()], else: fields
  end

  defp format_commit(%Build{git_commit_sha: sha, ci_project_handle: handle, ci_provider: "github"}) when handle != "" do
    short = String.slice(sha, 0, 7)
    "<https://github.com/#{handle}/commit/#{sha}|#{short}>"
  end

  defp format_commit(%Build{git_commit_sha: sha}) do
    "`#{String.slice(sha, 0, 7)}`"
  end

  defp format_environment(%Build{is_ci: true, ci_provider: provider}) when provider != "" and not is_nil(provider) do
    String.capitalize(provider)
  end

  defp format_environment(%Build{is_ci: true}), do: "CI"
  defp format_environment(_), do: "Local"

  defp format_cache_hit_rate(%Build{
         cacheable_tasks_count: total,
         cacheable_task_remote_hits_count: remote,
         cacheable_task_local_hits_count: local
       }) do
    hits = remote + local
    percentage = Float.round(hits / total * 100, 1)
    "#{percentage}% (#{hits}/#{total})"
  end

  defp build_tags_block(%Build{custom_tags: tags}) when is_list(tags) and tags != [] do
    [
      %{
        type: "context",
        elements: [
          %{type: "mrkdwn", text: ":label: #{Enum.join(tags, ", ")}"}
        ]
      }
    ]
  end

  defp build_tags_block(_), do: []

  defp mrkdwn_field(label, value) do
    %{type: "mrkdwn", text: "*#{label}:* #{value}"}
  end
end
