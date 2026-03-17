defmodule Tuist.Marketing.Blog.MDExConverter do
  @moduledoc """
  Custom NimblePublisher HTML converter that uses MDEx instead of Earmark.

  This converter does not render markdown to HTML at compile time. Instead,
  it returns the raw markdown body so that it can be rendered at runtime
  using MDEx.to_heex, which supports Phoenix LiveView components.
  """

  def convert(_path, body, _attrs, _opts) do
    body
  end
end
