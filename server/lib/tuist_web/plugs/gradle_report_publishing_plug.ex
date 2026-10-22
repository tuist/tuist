defmodule TuistWeb.Plugs.GradleReportPublishingPlug do
  @moduledoc """
  Gradle's report-creation adapter for the shared network publishing policy.
  """
  alias TuistWeb.Plugs.ReportPublishingPlug

  def init(opts), do: opts
  def call(conn, :preflight), do: ReportPublishingPlug.call(conn, {:preflight, :gradle})
  def call(conn, _opts), do: ReportPublishingPlug.call(conn, :gradle)
end
