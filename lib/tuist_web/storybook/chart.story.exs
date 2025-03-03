defmodule TuistWeb.Storybook.Chart do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.Chart.chart/1

  def variations do
    [
      %Variation{
        id: :line,
        attributes: %{
          option: %{
            xAxis: %{
              type: "category",
              data: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            },
            yAxis: %{
              type: "value"
            },
            series: [
              %{
                data: [120, 200, 150, 80, 70, 110, 130],
                type: "bar"
              }
            ]
          }
        }
      }
    ]
  end
end
