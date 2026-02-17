defmodule Tuist.MCP.Formatter do
  @moduledoc false

  def iso8601(value), do: iso8601(value, naive: :naive)

  def iso8601(nil, _opts), do: nil
  def iso8601(%DateTime{} = dt, _opts), do: DateTime.to_iso8601(dt)

  def iso8601(%NaiveDateTime{} = dt, opts) do
    case Keyword.get(opts, :naive, :naive) do
      :utc ->
        dt
        |> NaiveDateTime.truncate(:second)
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.to_iso8601()

      _ ->
        dt
        |> NaiveDateTime.truncate(:second)
        |> NaiveDateTime.to_iso8601()
    end
  end

  def iso8601(other, _opts), do: to_string(other)
end
