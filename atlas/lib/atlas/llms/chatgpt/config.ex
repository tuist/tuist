defmodule Atlas.LLMs.ChatGPT.Config do
  @moduledoc false

  alias Atlas.LLMs.ChatGPT

  def client_id do
    case Application.get_env(:atlas, ChatGPT, [])[:client_id] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :chatgpt_not_configured}
    end
  end
end
