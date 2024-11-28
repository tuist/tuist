defmodule TuistWeb.OpsConfigurationLive do
  @moduledoc false
  use Phoenix.LiveDashboard.PageBuilder

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
    rows = [
      %{name: "S3 region", value: Tuist.Environment.s3_region()},
      %{
        name: "S3 request timeout",
        value:
          Tuist.Environment.s3_request_timeout()
          |> Timex.Duration.from_seconds()
          |> Timex.Format.Duration.Formatters.Humanized.format()
      },
      %{
        name: "S3 pool timeout",
        value:
          Tuist.Environment.s3_pool_timeout()
          |> Timex.Duration.from_seconds()
          |> Timex.Format.Duration.Formatters.Humanized.format()
      },
      %{name: "S3 endpoint", value: Tuist.Environment.s3_endpoint()},
      %{
        name: "S3 authentication method",
        value: Tuist.Environment.s3_authentication_method() |> Atom.to_string()
      },
      %{name: "S3 bucket name", value: Tuist.Environment.s3_bucket_name()},
      %{name: "S3 connection pool size", value: Tuist.Environment.s3_pool_size()},
      %{name: "S3 connection pool count", value: Tuist.Environment.s3_pool_count()},
      %{
        name: "S3 connection protocol",
        value: Tuist.Environment.s3_protocol() |> Atom.to_string()
      }
    ]

    {rows, length(rows)}
  end
end
