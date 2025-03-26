defmodule TuistWeb.Storybook.Time do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.Time.time/1

  def template do
    """
    <div style="min-width: 300px; height: 80px;">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :default,
        attributes: %{
          time: ~U[2023-01-01 12:00:00Z]
        }
      },
      %Variation{
        id: :show_time,
        attributes: %{
          time: ~U[2023-01-01 12:00:00Z],
          show_time: true
        }
      },
      %Variation{
        id: :relative,
        attributes: %{
          time: ~U[2023-01-01 12:00:00Z],
          relative: true
        }
      }
    ]
  end
end
