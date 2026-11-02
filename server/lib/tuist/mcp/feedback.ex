defmodule Tuist.MCP.Feedback do
  @moduledoc """
  Publishes feedback that agents report through the MCP server to Atlas, where
  each report becomes a support conversation the Tuist team triages and can
  reply to by email.

  Report fields are written by the agent. Atlas stores them as untrusted
  customer input, like any other support message.
  """

  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.Environment
  alias Tuist.Projects
  alias Tuist.Repo

  @receive_timeout 5_000

  def enabled?, do: Environment.atlas_support_ingest_token() not in [nil, ""]

  def report(arguments, %User{} = user) do
    user = Repo.preload(user, :account)

    organization_handles =
      user |> Accounts.get_user_organization_accounts() |> Enum.map(& &1.account.name) |> Enum.sort()

    with {:ok, attribution} <- attribution(arguments, user, organization_handles) do
      body = %{
        "email" => user.email,
        "body" => message(arguments),
        "context" =>
          Map.merge(
            %{
              "tool_name" => arguments["tool_name"],
              "category" => arguments["category"],
              "tuist_user_id" => to_string(user.id),
              "tuist_user_handle" => user.account.name,
              "tuist_organization_handles" => organization_handles
            },
            attribution
          )
      }

      publish(body)
    end
  end

  def report(_arguments, _subject) do
    {:error, "Feedback can only be reported by an agent signed in as a Tuist user, so the team can reply."}
  end

  defp publish(body) do
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

  # The account and project the agent names are checked against the user's own
  # memberships, so a report can only be attributed to an organization the
  # reporting user belongs to. Support uses it to get back to that organization.
  defp attribution(%{"account_handle" => account_handle} = arguments, user, organization_handles)
       when is_binary(account_handle) do
    case Enum.find([user.account.name | organization_handles], &(String.downcase(&1) == String.downcase(account_handle))) do
      nil ->
        {:error,
         "The user is not a member of the Tuist account #{account_handle}. Use one of their accounts or leave account_handle out."}

      handle ->
        project_attribution(arguments["project_handle"], handle)
    end
  end

  defp attribution(%{"project_handle" => project_handle}, _user, _organization_handles) when is_binary(project_handle) do
    {:error, "project_handle requires account_handle."}
  end

  defp attribution(_arguments, _user, _organization_handles), do: {:ok, %{}}

  defp project_attribution(nil, account_handle), do: {:ok, %{"tuist_account_handle" => account_handle}}

  # An unknown project is dropped rather than failing the report: the account
  # is enough to get back to the customer.
  defp project_attribution(project_handle, account_handle) do
    case Projects.get_project_by_account_and_project_handles(account_handle, project_handle) do
      nil -> {:ok, %{"tuist_account_handle" => account_handle}}
      project -> {:ok, %{"tuist_account_handle" => account_handle, "tuist_project_handle" => project.name}}
    end
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
