defmodule TuistWeb.Storybook.Time do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.Time.time/1

  def template do
    """
    <div style="min-width: 300px; height: 80px;">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %VariationGroup{
        id: :display_formats,
        description: "Different time display formats",
        variations: [
          %Variation{
            id: :date_only,
            attributes: %{
              id: "time-date-only",
              time: ~U[2023-01-01 12:00:00Z]
            }
          },
          %Variation{
            id: :with_time,
            attributes: %{
              id: "time-with-time",
              time: ~U[2023-01-01 12:00:00Z],
              show_time: true
            }
          },
          %Variation{
            id: :relative,
            attributes: %{
              id: "time-relative",
              time: ~U[2023-01-01 12:00:00Z],
              relative: true
            }
          }
        ]
      },
      %VariationGroup{
        id: :different_times,
        description: "Various timestamps to show different scenarios",
        variations: [
          %Variation{
            id: :morning,
            attributes: %{
              id: "time-morning",
              time: ~U[2023-06-15 08:30:00Z],
              show_time: true
            }
          },
          %Variation{
            id: :evening,
            attributes: %{
              id: "time-evening",
              time: ~U[2023-06-15 19:45:00Z],
              show_time: true
            }
          },
          %Variation{
            id: :midnight,
            attributes: %{
              id: "time-midnight",
              time: ~U[2023-06-15 00:00:00Z],
              show_time: true
            }
          },
          %Variation{
            id: :noon,
            attributes: %{
              id: "time-noon",
              time: ~U[2023-06-15 12:00:00Z],
              show_time: true
            }
          }
        ]
      },
      %VariationGroup{
        id: :relative_times,
        description: "Relative time formatting examples",
        variations: [
          %Variation{
            id: :recent_past,
            attributes: %{
              id: "time-recent-past",
              time: ~U[2023-01-01 11:58:00Z],
              relative: true
            }
          },
          %Variation{
            id: :yesterday,
            attributes: %{
              id: "time-yesterday",
              time: ~U[2022-12-31 12:00:00Z],
              relative: true
            }
          },
          %Variation{
            id: :last_week,
            attributes: %{
              id: "time-last-week",
              time: ~U[2022-12-25 12:00:00Z],
              relative: true
            }
          },
          %Variation{
            id: :last_year,
            attributes: %{
              id: "time-last-year",
              time: ~U[2022-01-01 12:00:00Z],
              relative: true
            }
          }
        ]
      },
      %VariationGroup{
        id: :special_dates,
        description: "Special dates and edge cases",
        variations: [
          %Variation{
            id: :new_years,
            attributes: %{
              id: "time-new-years",
              time: ~U[2024-01-01 00:00:00Z],
              show_time: true
            }
          },
          %Variation{
            id: :leap_year,
            attributes: %{
              id: "time-leap-year",
              time: ~U[2024-02-29 12:00:00Z]
            }
          },
          %Variation{
            id: :far_future,
            attributes: %{
              id: "time-far-future",
              time: ~U[2030-12-31 23:59:59Z],
              show_time: true
            }
          }
        ]
      }
    ]
  end
end
