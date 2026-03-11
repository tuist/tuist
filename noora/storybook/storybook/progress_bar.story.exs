defmodule TuistWeb.Storybook.ProgressBar do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.ProgressBar.progress_bar/1

  def variations do
    [
      %VariationGroup{
        id: :basic,
        description: "Basic progress bar configurations",
        variations: [
          %Variation{
            id: :simple,
            attributes: %{
              id: "progress-bar-simple",
              value: 75,
              max: 100
            }
          },
          %Variation{
            id: :with_title,
            attributes: %{
              id: "progress-bar-with-title",
              value: 150,
              max: 200,
              title: "Storage Used:"
            }
          }
        ]
      },
      %VariationGroup{
        id: :progress_levels,
        description: "Different progress completion levels",
        variations: [
          %Variation{
            id: :empty,
            attributes: %{
              id: "progress-bar-empty",
              value: 0,
              max: 100,
              title: "Not started"
            }
          },
          %Variation{
            id: :quarter,
            attributes: %{
              id: "progress-bar-quarter",
              value: 25,
              max: 100,
              title: "25% Complete"
            }
          },
          %Variation{
            id: :half,
            attributes: %{
              id: "progress-bar-half",
              value: 50,
              max: 100,
              title: "Halfway there"
            }
          },
          %Variation{
            id: :three_quarters,
            attributes: %{
              id: "progress-bar-three-quarters",
              value: 75,
              max: 100,
              title: "Almost done"
            }
          },
          %Variation{
            id: :complete,
            attributes: %{
              id: "progress-bar-complete",
              value: 100,
              max: 100,
              title: "Complete!"
            }
          }
        ]
      },
      %VariationGroup{
        id: :different_scales,
        description: "Progress bars with different maximum values",
        variations: [
          %Variation{
            id: :small_scale,
            attributes: %{
              id: "progress-bar-small-scale",
              value: 3,
              max: 5,
              title: "Steps completed:"
            }
          },
          %Variation{
            id: :large_scale,
            attributes: %{
              id: "progress-bar-large-scale",
              value: 750,
              max: 1000,
              title: "Points earned:"
            }
          },
          %Variation{
            id: :file_download,
            attributes: %{
              id: "progress-bar-download",
              value: 847,
              max: 1024,
              title: "Download progress (MB):"
            }
          }
        ]
      },
      %VariationGroup{
        id: :edge_cases,
        description: "Edge cases and special scenarios",
        variations: [
          %Variation{
            id: :over_100_percent,
            attributes: %{
              id: "progress-bar-over-100",
              value: 120,
              max: 100,
              title: "Exceeded goal:"
            }
          },
          %Variation{
            id: :very_small_progress,
            attributes: %{
              id: "progress-bar-tiny",
              value: 1,
              max: 1000,
              title: "Just started:"
            }
          },
          %Variation{
            id: :long_title,
            attributes: %{
              id: "progress-bar-long-title",
              value: 42,
              max: 100,
              title: "Very Long Progress Bar Title That Might Wrap:"
            }
          }
        ]
      }
    ]
  end
end
