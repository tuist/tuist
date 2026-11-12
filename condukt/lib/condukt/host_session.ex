defmodule Condukt.HostSession do
  @moduledoc """
  The agent loop as a state machine, with the host doing the work.

  `Condukt.Session` runs a turn itself: it holds a process, calls the provider,
  executes tools, and hands back a result. That suits a host willing to let
  Condukt own those, and not one that would rather own its own inference and
  tool execution, or drive the loop inside a request it already has.

  This is the same loop with all of that removed. It holds conversation state
  and decides what should happen next; the host performs each step and reports
  back:

      session = HostSession.new(system_prompt: "Be useful", tools: tools)
      {:ok, request, session} = HostSession.submit(session, "What is here?")

      # The host calls its provider however it likes, then:
      {:ok, {:run_tools, _message, calls}, session} =
        HostSession.receive_completion(session, assistant_message)

      # The host runs those tools however it likes, then:
      {:ok, request, session} = HostSession.receive_tool_outputs(session, outputs)

  Every function returns the new session rather than mutating one, and nothing
  here performs input or output, sleeps, or spawns. That is what lets the same
  loop run inside a process, inside a request, or inside a page.

  It began as a transition-for-transition port of the Rust
  `condukt_session::HostSession` behind the `@tuist/condukt` browser package.
  That package and its crates are gone, so this is the only host-driven loop
  now and is free to change on its own terms. The system prompt travelling on
  the request rather than in history, which the Rust side did the other way,
  is the shape to keep: providers take it as its own parameter and
  `Condukt.Session` already treats it that way.
  """

  alias Condukt.Message

  # A host that wants a different ceiling bounds its own loop; this exists so a
  # model that keeps asking for tools cannot run forever unattended.
  @max_iterations 16

  defstruct history: [],
            system_prompt: nil,
            tools: [],
            awaiting_completion: false,
            awaiting_tools: nil,
            iterations: 0

  @doc """
  Starts a conversation.

  ## Options

    * `:system_prompt` - opening instructions, carried on every request rather
      than pushed into history, which is how `Condukt.Session` and every
      provider treat it
    * `:tools` - tool definitions passed to the provider on every request
  """
  def new(opts \\ []) do
    prompt = opts |> Keyword.get(:system_prompt) |> presence()

    %__MODULE__{
      system_prompt: prompt,
      tools: Keyword.get(opts, :tools, [])
    }
  end

  @doc "The conversation so far, oldest first."
  def history(%__MODULE__{history: history}), do: history

  @doc """
  Begins a turn and returns the request the host should complete.

  Returns `{:error, :turn_in_progress}` when the previous turn has not
  finished, because appending a second user message mid-turn would reorder the
  conversation the model is answering.
  """
  def submit(%__MODULE__{} = session, prompt) do
    if in_progress?(session) do
      {:error, :turn_in_progress}
    else
      session
      |> Map.put(:iterations, 0)
      |> append(Message.user(prompt))
      |> next_request()
    end
  end

  @doc """
  Accepts the model's reply.

  Returns `{:ok, {:complete, message}, session}` when the turn is over, or
  `{:ok, {:run_tools, message, calls}, session}` when the host has tools to run
  before asking again.
  """
  def receive_completion(%__MODULE__{awaiting_completion: false}, _response) do
    {:error, :not_waiting_for_completion}
  end

  def receive_completion(%__MODULE__{}, %Message{role: role}) when role != :assistant do
    {:error, :invalid_response_role}
  end

  def receive_completion(%__MODULE__{} = session, %Message{} = response) do
    session = session |> Map.put(:awaiting_completion, false) |> append(response)

    case Message.tool_calls(response) do
      [] -> {:ok, {:complete, response}, session}
      calls -> {:ok, {:run_tools, response, calls}, %{session | awaiting_tools: calls}}
    end
  end

  @doc """
  Accepts one result per requested tool call and asks the model to continue.

  Outputs are `%{tool_call_id: id, content: content, error?: boolean}`. They may
  arrive in any order, but every requested call needs exactly one result:
  a mismatch leaves the session waiting rather than sending the model a turn
  that does not answer what it asked, so the host can retry.
  """
  def receive_tool_outputs(%__MODULE__{awaiting_tools: nil}, _outputs) do
    {:error, :not_waiting_for_tools}
  end

  def receive_tool_outputs(%__MODULE__{awaiting_tools: calls} = session, outputs) do
    if answers?(calls, outputs) do
      session
      |> Map.put(:awaiting_tools, nil)
      |> append_results(calls, outputs)
      |> next_request()
    else
      {:error, :invalid_tool_results}
    end
  end

  @doc "Whether a turn is waiting on the host."
  def in_progress?(%__MODULE__{awaiting_completion: true}), do: true
  def in_progress?(%__MODULE__{awaiting_tools: tools}) when is_list(tools), do: true
  def in_progress?(%__MODULE__{}), do: false

  # Every requested call answered exactly once, and nothing answered that was
  # not asked for.
  defp answers?(calls, outputs) do
    requested = Enum.map(calls, fn {id, _name, _args} -> id end)
    answered = Enum.map(outputs, & &1.tool_call_id)

    length(requested) == length(answered) and Enum.sort(requested) == Enum.sort(answered)
  end

  # Results are appended in the order the calls were requested, not the order
  # they were answered, so the transcript reads the way the model asked for it.
  defp append_results(session, calls, outputs) do
    by_id = Map.new(outputs, &{&1.tool_call_id, &1})

    Enum.reduce(calls, session, fn {id, _name, _args}, acc ->
      append(acc, Message.tool_result(id, content_of(Map.fetch!(by_id, id))))
    end)
  end

  defp content_of(%{error?: true, content: content}), do: "Tool error: #{content}"
  defp content_of(%{content: content}), do: content

  defp next_request(%__MODULE__{iterations: iterations}) when iterations >= @max_iterations do
    {:error, :iteration_limit}
  end

  defp next_request(%__MODULE__{} = session) do
    session = %{session | iterations: session.iterations + 1, awaiting_completion: true}
    request = %{messages: session.history, tools: session.tools, system_prompt: session.system_prompt}
    {:ok, request, session}
  end

  defp append(%__MODULE__{history: history} = session, message) do
    %{session | history: history ++ [message]}
  end

  defp presence(nil), do: nil

  defp presence(value) when is_binary(value) do
    if String.trim(value) != "", do: value
  end
end
