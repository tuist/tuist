defmodule Condukt.Message do
  @moduledoc """
  Represents a message in the conversation history.

  Messages can be from the user, the assistant, or represent tool results.
  Assistant messages may include tool calls and their results.

  ## Message Roles

  - `:user` - A message from the user
  - `:assistant` - A response from the LLM
  - `:tool_result` - The result of a tool execution

  ## Content Blocks

  Assistant messages can contain multiple content blocks:

  - `{:text, string}` - Plain text
  - `{:thinking, string}` - Model's reasoning (if thinking enabled)
  - `{:reasoning_details, list}` - Opaque ReqLLM reasoning state for provider replay,
    not display text. Session stores must protect this along with conversation content.
  - `{:tool_call, id, name, args}` - A tool invocation
  """

  @enforce_keys [:role, :content]
  defstruct [:role, :content, :tool_call_id, images: [], timestamp: nil]

  @doc """
  Creates a new user message.

  ## Examples

      Message.user("Hello!")
      Message.user("What's in this image?", [%{type: :base64, media_type: "image/png", data: "..."}])
  """
  def user(text, images \\ []) do
    %__MODULE__{
      role: :user,
      content: text,
      images: images,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Creates a new assistant message.

  Content can be a string or a list of content blocks.
  """
  def assistant(content) do
    %__MODULE__{
      role: :assistant,
      content: content,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Creates a tool result message.

  The content will be JSON-encoded if not a string.
  """
  def tool_result(tool_call_id, content) do
    %__MODULE__{
      role: :tool_result,
      content: content,
      tool_call_id: tool_call_id,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Extracts plain text from a message's content.

  Returns the concatenated text blocks for assistant messages,
  or the content directly for user messages.
  """
  def text(%__MODULE__{content: content}) when is_binary(content), do: content

  def text(%__MODULE__{content: blocks}) when is_list(blocks) do
    blocks
    |> Enum.filter(&match?({:text, _}, &1))
    |> Enum.map_join("", fn {:text, text} -> text end)
  end

  def text(%__MODULE__{content: content}), do: inspect(content)

  @doc """
  Extracts the content from a tool result message for display.
  """
  def tool_result_content(%__MODULE__{role: :tool_result, content: content}), do: content

  @doc """
  Checks if the message contains any tool calls.
  """
  def has_tool_calls?(%__MODULE__{content: blocks}) when is_list(blocks) do
    Enum.any?(blocks, &match?({:tool_call, _, _, _}, &1))
  end

  def has_tool_calls?(_), do: false

  @doc """
  Extracts tool calls from a message.

  Returns a list of `{id, name, args}` tuples.
  """
  def tool_calls(%__MODULE__{content: blocks}) when is_list(blocks) do
    blocks
    |> Enum.filter(&match?({:tool_call, _, _, _}, &1))
    |> Enum.map(fn {:tool_call, id, name, args} -> {id, name, args} end)
  end

  def tool_calls(_), do: []

  @doc """
  Extracts thinking content from a message.
  """
  def thinking(%__MODULE__{content: blocks}) when is_list(blocks) do
    blocks
    |> Enum.filter(&match?({:thinking, _}, &1))
    |> Enum.map_join("", fn {:thinking, text} -> text end)
    |> case do
      "" -> nil
      text -> text
    end
  end

  def thinking(_), do: nil
end
