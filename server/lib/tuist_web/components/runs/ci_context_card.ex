defmodule TuistWeb.Runs.CIContextCard do
  @moduledoc """
  Shared CI details card for build and test detail pages.
  """
  use TuistWeb, :html
  use Noora

  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.RunnerJobLive

  attr :context, :map, required: true

  def ci_context_card(assigns) do
    ~H"""
    <div class="tuist-ci-context-card">
      <% job = @context.runner_job %>
      <.card
        title={dgettext("dashboard_runners", "CI Details")}
        icon="git_merge"
        data-part="ci-context-card"
      >
        <:actions>
          <.button
            :if={@context.runner_job_path}
            navigate={@context.runner_job_path}
            label={dgettext("dashboard_runners", "View more")}
            variant="secondary"
            size="medium"
          />
        </:actions>
        <.card_section data-part="ci-context-section">
          <div data-part="ci-context-grid">
            <div data-part="ci-context-metadata">
              <div data-part="title">{dgettext("dashboard_runners", "Workflow")}</div>
              <span data-part="label">
                <.link
                  :if={@context.workflow_path}
                  navigate={@context.workflow_path}
                  data-part="label-link"
                >
                  {display_value(job.workflow_name)}
                </.link>
                <span :if={!@context.workflow_path}>{display_value(job.workflow_name)}</span>
              </span>
            </div>
            <div data-part="ci-context-metadata">
              <div data-part="title">{dgettext("dashboard_runners", "Job")}</div>
              <span data-part="label">
                <.link
                  :if={@context.runner_job_path}
                  navigate={@context.runner_job_path}
                  data-part="label-link"
                >
                  {display_value(job.job_name)}
                </.link>
                <span :if={!@context.runner_job_path}>{display_value(job.job_name)}</span>
              </span>
            </div>
            <div data-part="ci-context-metadata">
              <div data-part="title">{dgettext("dashboard_runners", "Profile")}</div>
              <span data-part="command-label">{profile_label(job)}</span>
            </div>
            <div data-part="ci-context-metadata">
              <div data-part="title">{dgettext("dashboard_runners", "Queue time")}</div>
              <span data-part="label">
                <.history />
                {duration_label(RunnerJobLive.queued_duration_ms(job))}
              </span>
            </div>
            <div data-part="ci-context-metadata">
              <div data-part="title">{dgettext("dashboard_runners", "CI job duration")}</div>
              <span data-part="label">
                <.history />
                {duration_label(RunnerJobLive.run_duration_ms(job))}
              </span>
            </div>
            <div data-part="ci-context-metadata">
              <div data-part="title">{dgettext("dashboard_runners", "Step")}</div>
              <span data-part="label">
                <.subtask />
                <.link
                  :if={@context.matched_step_path && @context.matched_step}
                  navigate={@context.matched_step_path}
                  data-part="label-link"
                >
                  {matched_step_label(@context.matched_step)}
                </.link>
                <span :if={!@context.matched_step_path || !@context.matched_step}>
                  {matched_step_label(@context.matched_step)}
                </span>
              </span>
            </div>
          </div>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp display_value(value) when value in [nil, ""], do: dgettext("dashboard_runners", "Unknown")
  defp display_value(value), do: value

  defp profile_label(%{requested_dispatch_label: label}) when label not in [nil, ""] do
    label
  end

  defp profile_label(job), do: display_value(job.fleet_name)

  defp duration_label(duration_ms) do
    DateFormatter.format_duration_from_milliseconds(duration_ms, fractional_seconds: false)
  end

  defp matched_step_label(nil), do: dgettext("dashboard_runners", "Not recorded")

  defp matched_step_label(step) do
    duration = step |> RunnerJobLive.step_duration_ms() |> duration_label()
    "#{display_value(step.name)} · #{duration}"
  end
end
