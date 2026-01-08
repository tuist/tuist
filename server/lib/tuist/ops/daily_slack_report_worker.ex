defmodule Tuist.Ops.DailySlackReportWorker do
  @moduledoc """
  A worker that runs daily and sends a report about the business to Slack.
  """
  use Oban.Worker

  import Ecto.Query, only: [from: 2]

  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.User
  alias Tuist.CommandEvents
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Slack

  @impl Oban.Worker
  def perform(_job) do
    {_, today, _, _} = dates = get_dates()
    user_numbers = growth(User, dates)
    organization_numbers = growth(Organization, dates)
    project_numbers = growth(Project, dates)
    command_event_numbers = growth_command_events(dates)

    :ok =
      Slack.send_message([
        %{
          type: "header",
          text: %{
            type: "plain_text",
            text: "Daily report #{Timex.format!(today, "{D}.{M}.{YYYY}")} 📈 (#{Atom.to_string(Tuist.Environment.env())})"
          }
        },
        %{
          type: "context",
          elements: [
            %{
              type: "plain_text",
              text: "Great things start small—believe in your vision and keep pushing forward."
            }
          ]
        },
        %{
          type: "section",
          text: %{
            type: "plain_text",
            text:
              "The following data represents data from Monday to today, and its growth compared to the same weekday last week:\n"
          }
        },
        %{
          type: "rich_text",
          elements: [
            %{type: "rich_text_section", elements: []},
            %{
              type: "rich_text_list",
              style: "bullet",
              elements: [
                %{
                  type: "rich_text_section",
                  elements: [
                    %{type: "text", text: "👩‍💻 Users: ", style: %{bold: true}},
                    %{type: "text", text: format_numbers(user_numbers)}
                  ]
                },
                %{
                  type: "rich_text_section",
                  elements: [
                    %{type: "text", text: "💼 Organizations: ", style: %{bold: true}},
                    %{type: "text", text: format_numbers(organization_numbers)}
                  ]
                },
                %{
                  type: "rich_text_section",
                  elements: [
                    %{type: "text", text: "⚙️ Projects: ", style: %{bold: true}},
                    %{type: "text", text: format_numbers(project_numbers)}
                  ]
                },
                %{
                  type: "rich_text_section",
                  elements: [
                    %{type: "text", text: "▶️ Command events: ", style: %{bold: true}},
                    %{type: "text", text: format_numbers(command_event_numbers)}
                  ]
                }
              ]
            }
          ]
        }
      ])

    :ok
  end

  defp format_numbers({this_week, total, growth}) do
    ~s"""
    #{this_week} created (#{if growth >= 0, do: "↑ #{growth}%", else: "↓ #{growth}%"}) | Total: #{Number.Human.number_to_human(total, precision: 0)}
    """
  end

  defp growth(model, {beginning_of_this_week, today, beginning_of_last_week, same_weekday_last_week}) do
    this_week =
      Repo.aggregate(
        from(e in model,
          where:
            fragment(
              "? >= ? AND ? <= ?",
              e.created_at,
              ^beginning_of_this_week,
              e.created_at,
              ^today
            )
        ),
        :count
      )

    last_week =
      Repo.aggregate(
        from(e in model,
          where:
            fragment(
              "? >= ? AND ? <= ?",
              e.created_at,
              ^beginning_of_last_week,
              e.created_at,
              ^same_weekday_last_week
            )
        ),
        :count
      )

    total = Repo.aggregate(from(e in model, []), :count)

    {this_week, total, percentage_increase(this_week, last_week)}
  end

  defp get_beginning_of_week(date) do
    Timex.beginning_of_week(date, :monday)
    # Assuming week starts on Monday
  end

  defp get_dates do
    today = Tuist.Time.utc_now()

    beginning_of_this_week = get_beginning_of_week(today)
    beginning_of_last_week = Timex.shift(beginning_of_this_week, days: -7)
    same_weekday_last_week = Timex.shift(today, days: -7)

    {beginning_of_this_week, today, beginning_of_last_week, same_weekday_last_week}
  end

  defp percentage_increase(_, previous_count) when previous_count == 0 do
    0.0
  end

  defp percentage_increase(current_count, previous_count) do
    increase = (current_count - previous_count) / previous_count * 100
    Float.round(increase, 1)
  end

  defp growth_command_events({beginning_of_this_week, today, beginning_of_last_week, same_weekday_last_week}) do
    this_week = CommandEvents.count_events_in_period(beginning_of_this_week, today)

    last_week =
      CommandEvents.count_events_in_period(beginning_of_last_week, same_weekday_last_week)

    total = CommandEvents.count_all_events()

    {this_week, total, percentage_increase(this_week, last_week)}
  end
end
