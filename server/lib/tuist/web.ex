defmodule Tuist.Web do
  @moduledoc """
  The web endpoint and router, resolved from configuration at runtime.

  Core modules use these instead of naming `TuistWeb.Endpoint` or
  `TuistWeb.Router`. A module name in code is a runtime dependency, and the
  router depends on every controller and LiveView, so naming either from core
  makes every module that uses core at compile time recompile whenever any web
  module changes.
  """

  def endpoint, do: Application.fetch_env!(:tuist, :web_endpoint)

  def router, do: Application.fetch_env!(:tuist, :web_router)
end
