defmodule TuistWeb.API.BuildEntityResources do
  @moduledoc false

  alias Tuist.BuildEntities.Resources

  defdelegate all(), to: Resources
  defdelegate dashboard_resources(), to: Resources
  defdelegate fetch!(key), to: Resources
  defdelegate for_project(project), to: Resources
end
