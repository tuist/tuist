defmodule Tuist.MCP.Content do
  @moduledoc false

  def ok_json(data), do: {:ok, json(data)}

  def json(data) do
    %{
      content: [
        %{
          type: "text",
          text: JSON.encode!(data)
        }
      ]
    }
  end
end
