defmodule LuftServer.Threads.Clients do
  @moduledoc "Ephemeral app tools routed only to the original message author's connected apps."
  use Phoenix.Presence,
    otp_app: :luft_server,
    pubsub_server: LuftServer.PubSub,
    broadcast_period: 200

  @prefix "client_"
  @max_result 8_000
  def prefix, do: @prefix

  def validate(nil), do: {:ok, []}

  def validate(tools) when is_list(tools) and length(tools) <= 8 do
    tools
    |> Enum.reduce_while({:ok, []}, fn tool, {:ok, valid} ->
      case validate_tool(tool) do
        {:ok, tool} -> {:cont, {:ok, valid ++ [tool]}}
        :error -> {:halt, {:error, :invalid_tools}}
      end
    end)
    |> case do
      {:ok, valid} ->
        names = Enum.map(valid, & &1.name)
        if Enum.uniq(names) == names, do: {:ok, valid}, else: {:error, :invalid_tools}

      error ->
        error
    end
  end

  def validate(_), do: {:error, :invalid_tools}

  defp validate_tool(%{
         "name" => name,
         "description" => description,
         "parameters" => %{"type" => "object"} = params
       })
       when is_binary(name) and is_binary(description) do
    if name =~ ~r/\A[a-z][a-z0-9_]{0,47}\z/ and String.trim(description) != "" and
         String.length(description) <= 4_000 and byte_size(Jason.encode!(params)) <= 16_384,
       do: {:ok, %{name: name, description: description, parameters: params}},
       else: :error
  end

  defp validate_tool(_), do: :error

  def topic(thread_id), do: "thread_clients:#{thread_id}"

  def join(thread_id, user_id, tools) do
    track(self(), topic(thread_id), inspect(self()), %{
      pid: self(),
      user_id: user_id,
      tools: tools,
      joined_at: System.system_time(:microsecond)
    })
  end

  def tools(thread_id, user_id),
    do: thread_id |> clients(user_id) |> Enum.flat_map(& &1.tools) |> Enum.uniq_by(& &1.name)

  def await_tools(thread_id, user_id, timeout) do
    await(thread_id, user_id, System.monotonic_time(:millisecond) + timeout)
  end

  defp await(thread_id, user_id, deadline) do
    case tools(thread_id, user_id) do
      [] ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(100)
          await(thread_id, user_id, deadline)
        else
          []
        end

      tools ->
        tools
    end
  end

  def call(thread_id, user_id, name, args, timeout \\ 30_000) do
    case Enum.find(clients(thread_id, user_id), fn client ->
           Enum.any?(client.tools, &(&1.name == name))
         end) do
      nil ->
        {:error,
         "The person's app isn't showing this thread anymore, so it can't run #{@prefix}#{name}."}

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

  def result(%{"ok" => text}) when is_binary(text), do: {:ok, String.slice(text, 0, @max_result)}

  def result(%{"error" => text}) when is_binary(text),
    do: {:error, String.slice(text, 0, @max_result)}

  def result(_), do: {:error, "The person's app answered with an invalid result."}

  defp clients(thread_id, user_id) do
    thread_id
    |> topic()
    |> list()
    |> Enum.flat_map(fn {_key, %{metas: metas}} -> metas end)
    |> Enum.filter(&(&1.user_id == user_id))
    |> Enum.sort_by(& &1.joined_at, :desc)
  end
end
