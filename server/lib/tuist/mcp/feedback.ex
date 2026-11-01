defmodule Tuist.MCP.Feedback do
  @moduledoc """
  Publishes feedback that agents report through the MCP server to Atlas, where
  each report becomes a support conversation the Tuist team triages and can
  reply to by email.

  Report fields are written by the agent. Atlas stores them as untrusted
  customer input, like any other support message.
  """

  alias Tuist.Accounts.User
  alias Tuist.Environment

  @receive_timeout 5_000

  def enabled?, do: Environment.atlas_support_ingest_token() not in [nil, ""]

  def report(arguments, %User{} = user) do
    body = %{
      "email" => user.email,
      "body" => message(arguments),
      "context" => %{
        "tool_name" => arguments["tool_name"],
        "category" => arguments["category"],
        "tuist_user_id" => to_string(user.id)
      }
    }

    case Req.post(Environment.atlas_url() <> "/api/support/agent-feedback",
           json: body,
           auth: {:bearer, Environment.atlas_support_ingest_token()},
           receive_timeout: @receive_timeout,
           connect_options: [timeout: 2_000],
           retry: false
         ) do
      {:ok, %Req.Response{status: 201, body: %{"id" => id}}} ->
        {:ok, %{feedback_id: id}}

      {:ok, %Req.Response{status: 429}} ->
        {:error, "Too many feedback reports from this user. Try again later."}

      {:ok, %Req.Response{status: status}} ->
        {:error, "Feedback could not be delivered (HTTP #{status})."}

      {:error, error} ->
        {:error, "Feedback could not be delivered: #{Exception.message(error)}"}
    end
  end

  def report(_arguments, _subject) do
    {:error, "Feedback can only be reported by an agent signed in as a Tuist user, so the team can reply."}
  end

  defp message(arguments) do
    [
      {"Expected", arguments["expected"]},
      {"Actual", arguments["actual"]},
      {"Suggestion", arguments["suggestion"]}
    ]
    |> Enum.reject(fn {_label, value} -> value in [nil, ""] end)
    |> Enum.map_join("\n\n", fn {label, value} -> "#{label}:\n#{value}" end)
  end
end
