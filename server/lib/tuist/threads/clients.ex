defmodule Tuist.Threads.Clients do
  @moduledoc """
  Tools the person's app exposes to a thread's agent while it shows that
  thread, such as Tuist Guild's `set_theme`.

  An app offers its tools when it joins the thread's channel
  (`TuistWeb.ThreadsChannel`), which tracks itself here with them and its
  signed-in user, so the host of the thread's runs sees them on whichever
  node it runs. A run offers the model the tools that its author's apps
  present when it starts, named `client_<name>`, and `call/5` sends each
  call to the channel of that person's latest app that offers the tool,
  which pushes it to the app and sends its answer back. Another person's
  app showing the same thread is never offered or called. Nothing is
  stored: an app that disconnects takes its tools with it, and a call to a
  tool no connected app offers fails.

  Tracked metadata reaches other nodes once per `broadcast_period`.
  """
  use Phoenix.Presence,
    otp_app: :tuist,
    pubsub_server: Tuist.PubSub,
    broadcast_period: 200

  @prefix "client_"
  @max_tools 8
  @max_description 4_000
  @max_parameters 16_384
  @call_timeout 30_000
  @max_result 8_000

  def prefix, do: @prefix

  @doc """
  Validates the tools an app offers in its join payload: at most #{@max_tools}
  with distinct snake_case names, a description and an object JSON schema.
  """
  def validate(nil), do: {:ok, []}

  def validate(tools) when is_list(tools) and length(tools) <= @max_tools do
    tools
    |> Enum.reduce_while({:ok, []}, fn tool, {:ok, valid} ->
      case validate_tool(tool) do
        {:ok, tool} -> {:cont, {:ok, [tool | valid]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, valid} ->
        names = Enum.map(valid, & &1.name)
        if Enum.uniq(names) == names, do: {:ok, Enum.reverse(valid)}, else: {:error, :invalid_tools}

      :error ->
        {:error, :invalid_tools}
    end
  end

  def validate(_tools), do: {:error, :invalid_tools}

  defp validate_tool(%{"name" => name, "description" => description, "parameters" => %{"type" => "object"} = parameters})
       when is_binary(name) and is_binary(description) do
    if name =~ ~r/\A[a-z][a-z0-9_]{0,47}\z/ and String.trim(description) != "" and
         String.length(description) <= @max_description and
         byte_size(JSON.encode!(parameters)) <= @max_parameters do
      {:ok, %{name: name, description: description, parameters: parameters}}
    else
      :error
    end
  end

  defp validate_tool(_tool), do: :error

  def topic(thread_id), do: "thread_clients:#{thread_id}"

  @doc "Tracks the calling channel as `user_id`'s app showing the thread with `tools`."
  def join(thread_id, user_id, tools) do
    meta = %{pid: self(), user_id: user_id, tools: tools, joined_at: System.system_time(:microsecond)}
    track(self(), topic(thread_id), inspect(self()), meta)
  end

  @doc """
  The tools `user_id`'s apps showing the thread offer, each name once, from
  the latest app that offers it.
  """
  def tools(thread_id, user_id) do
    thread_id
    |> clients(user_id)
    |> Enum.flat_map(& &1.tools)
    |> Enum.uniq_by(& &1.name)
  end

  @doc """
  Waits up to `timeout` milliseconds for one of `user_id`'s apps to show the
  thread, as when a thread was just started and its app is still opening it.
  """
  def await_tools(thread_id, user_id, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    await_tools(thread_id, user_id, deadline, tools(thread_id, user_id))
  end

  defp await_tools(thread_id, user_id, deadline, []) do
    if System.monotonic_time(:millisecond) < deadline do
      Process.sleep(100)
      await_tools(thread_id, user_id, deadline, tools(thread_id, user_id))
    else
      []
    end
  end

  defp await_tools(_thread_id, _user_id, _deadline, tools), do: tools

  @doc """
  Calls the app tool `name` with `args` in `user_id`'s latest app that offers
  it, and waits for its answer: `{:ok, text}` or `{:error, reason}`.
  """
  def call(thread_id, user_id, name, args, timeout \\ @call_timeout) do
    case Enum.find(clients(thread_id, user_id), fn client -> Enum.any?(client.tools, &(&1.name == name)) end) do
      nil ->
        {:error, "The person's app isn't showing this thread anymore, so it can't run #{@prefix}#{name}."}

      %{pid: pid} ->
        ref = make_ref()
        monitor = Process.monitor(pid)
        send(pid, {:client_tool_call, ref, self(), name, args, timeout})

        receive do
          {:client_tool_result, ^ref, result} ->
            Process.demonitor(monitor, [:flush])
            result

          {:DOWN, ^monitor, :process, _pid, _reason} ->
            {:error, "The person's app disconnected before #{@prefix}#{name} finished."}
        after
          timeout ->
            Process.demonitor(monitor, [:flush])
            {:error, "The person's app didn't answer #{@prefix}#{name} in time."}
        end
    end
  end

  @doc "The answer an app pushed for a call, as `call/5` returns it."
  def result(%{"ok" => text}) when is_binary(text), do: {:ok, String.slice(text, 0, @max_result)}
  def result(%{"error" => text}) when is_binary(text), do: {:error, String.slice(text, 0, @max_result)}
  def result(_payload), do: {:error, "The person's app answered with an invalid result."}

  defp clients(thread_id, user_id) do
    thread_id
    |> topic()
    |> list()
    |> Enum.flat_map(fn {_key, %{metas: metas}} -> metas end)
    |> Enum.filter(&(&1.user_id == user_id))
    |> Enum.sort_by(& &1.joined_at, :desc)
  end
end
