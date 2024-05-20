defmodule TuistCloud.Ops.DailySlackReportWorker do
  @moduledoc """
  A worker that runs daily and sends a report about the business to Slack.
  """
  use Oban.Worker
  import Ecto.Query, only: [from: 2]
  alias TuistCloud.Slack
  alias TuistCloud.Repo
  alias TuistCloud.Accounts.{Organization, User}
  alias TuistCloud.CommandEvents.CacheEvent
  alias TuistCloud.CommandEvents.Event
  alias TuistCloud.Projects.Project

  @impl Oban.Worker
  def perform(_job) do
    {_, today, _, _} = dates = get_dates()
    user_numbers = growth(User, dates)
    organization_numbers = growth(Organization, dates)
    project_numbers = growth(Project, dates)
    cache_event_numbers = growth(CacheEvent, dates)
    command_event_numbers = growth(Event, dates)

    :ok =
      Slack.send_message([
        %{
          type: "header",
          text: %{
            type: "plain_text",
            text: "Daily report #{Timex.format!(today, "{D}.{M}.{YYYY}")} 📈"
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
                    %{type: "text", text: "📦 Cache events: ", style: %{bold: true}},
                    %{type: "text", text: format_numbers(cache_event_numbers)}
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

  defp growth(
         model,
         {beginning_of_this_week, today, beginning_of_last_week, same_weekday_last_week}
       ) do
    this_week =
      from(e in model,
        where:
          fragment(
            "? >= ? AND ? <= ?",
            e.created_at,
            ^beginning_of_this_week,
            e.created_at,
            ^today
          )
      )
      |> Repo.aggregate(:count)

    last_week =
      from(e in model,
        where:
          fragment(
            "? >= ? AND ? <= ?",
            e.created_at,
            ^beginning_of_last_week,
            e.created_at,
            ^same_weekday_last_week
          )
      )
      |> Repo.aggregate(:count)

    total = from(e in model, []) |> Repo.aggregate(:count)

    {this_week, total, percentage_increase(this_week, last_week)}
  end

  defp get_beginning_of_week(date) do
    date
    # Assuming week starts on Monday
    |> Timex.beginning_of_week(:monday)
  end

  defp get_dates() do
    today = TuistCloud.Time.utc_now()

    beginning_of_this_week = get_beginning_of_week(today)
    beginning_of_last_week = beginning_of_this_week |> Timex.shift(days: -7)
    same_weekday_last_week = today |> Timex.shift(days: -7)

    {beginning_of_this_week, today, beginning_of_last_week, same_weekday_last_week}
  end

  defp percentage_increase(_, previous_count) when previous_count == 0 do
    0.0
  end

  defp percentage_increase(current_count, previous_count) do
    increase = (current_count - previous_count) / previous_count * 100
    rounded_increase = Float.round(increase, 0)
    trunc(rounded_increase)
  end
end
