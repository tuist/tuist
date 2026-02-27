defmodule Tuist.MCP.Authorization do
  @moduledoc false

  alias Tuist.Authorization

  def authorize(subject, action, resource, category) do
    Authorization.authorize(:"#{category}_#{action}", subject, resource) == :ok
  end

  def authenticated_subject(assigns) when is_map(assigns) do
    assigns[:current_subject] || assigns[:current_user] || assigns[:current_project]
  end
end
