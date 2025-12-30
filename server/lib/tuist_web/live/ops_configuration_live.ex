defmodule TuistWeb.OpsConfigurationLive do
  @moduledoc false
  use Phoenix.LiveDashboard.PageBuilder

  alias Timex.Format.Duration.Formatters.Humanized

  @impl true
  def menu_link(_, _) do
    {:ok, "Configuration"}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_table
      id="configuration-table"
      search={true}
      dom_id="configuration-table"
      page={@page}
      title="Configuration"
      row_fetcher={&fetch_rows/2}
    >
      <:col sortable={:asc} field={:name} header="Attribute name" />
      <:col field={:value} header="Attribute value" />
    </.live_table>
    """
  end

  defp fetch_rows(_params, _node) do
    version = Tuist.Environment.version()

    rows = [
      # Displaying the version helps identify the running application version for debugging and operational purposes.
      %{name: "Version", value: "#{version}"},
      %{name: "S3 region", value: Tuist.Environment.s3_region()},
      %{
        name: "S3 connect timeout",
        value:
          Tuist.Environment.s3_connect_timeout()
          |> Timex.Duration.from_milliseconds()
          |> Humanized.format()
      },
      %{
        name: "S3 receive timeout",
        value:
          Tuist.Environment.s3_receive_timeout()
          |> Timex.Duration.from_milliseconds()
          |> Humanized.format()
      },
      %{
        name: "S3 pool timeout",
        value:
          case Tuist.Environment.s3_pool_timeout() do
            :infinity -> "Infinity"
            timeout -> timeout |> Timex.Duration.from_milliseconds() |> Humanized.format()
          end
      },
      %{
        name: "S3 pool max idle time",
        value:
          case Tuist.Environment.s3_pool_max_idle_time() do
            :infinity -> "Infinity"
            timeout -> timeout |> Timex.Duration.from_milliseconds() |> Humanized.format()
          end
      },
      %{name: "S3 endpoint", value: Tuist.Environment.s3_endpoint()},
      %{
        name: "S3 authentication method",
        value: Atom.to_string(Tuist.Environment.s3_authentication_method())
      },
      %{name: "S3 bucket name", value: Tuist.Environment.s3_bucket_name()},
      %{name: "S3 connection pool size", value: Tuist.Environment.s3_pool_size()},
      %{name: "S3 connection pool count", value: Tuist.Environment.s3_pool_count()},
      %{
        name: "S3 connection protocol",
        value: JSON.encode!(Tuist.Environment.s3_protocols())
      }
    ]

    {rows, length(rows)}
  end
end
