defmodule Tuist.MCP.Components.Tools.UpdateTestCase do
  @moduledoc """
  Update mutable fields on a test case. Supports changing `state` between `enabled` and `muted` and toggling `is_flaky`. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}.
  """

  use Tuist.MCP.Tool,
    name: "update_test_case",
    schema: %{
      "type" => "object",
      "properties" => %{
        "test_case_id" => %{
          "type" => "string",
          "description" => "The ID of the test case. Required when not using identifier lookup."
        },
        "account_handle" => %{
          "type" => "string",
          "description" => "The account handle (organization or user). Required for identifier lookup."
        },
        "project_handle" => %{
          "type" => "string",
          "description" => "The project handle. Required for identifier lookup."
        },
        "identifier" => %{
          "type" => "string",
          "description" =>
            "Test case identifier in Module/Suite/TestCase or Module/TestCase format. " <>
              "Required when not using test_case_id. Must be combined with account_handle and project_handle."
        },
        "state" => %{
          "type" => "string",
          "enum" => ["enabled", "muted"],
          "description" => "The new state of the test case."
        },
        "is_flaky" => %{
          "type" => "boolean",
          "description" => "Whether to mark the test case as flaky."
        }
      }
    }

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.MCP.Authorization
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Projects.Project
  alias Tuist.Tests

  @authorization_action :update
  @authorization_category :test

  @impl EMCP.Tool
  def description,
    do:
      "Update mutable fields on a test case. Supports changing `state` between `enabled` and `muted` and toggling `is_flaky`. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  @impl EMCP.Tool
  def call(conn, args) do
    case extract_update_attrs(args) do
      {:ok, attrs} -> resolve_and_update(conn, args, attrs)
      {:error, message} -> EMCP.Tool.error(message)
    end
  end

  defp resolve_and_update(conn, %{"test_case_id" => test_case_id} = _args, attrs) when is_binary(test_case_id) do
    case MCPTool.load_and_authorize(
           Tests.get_test_case_by_id(test_case_id),
           conn.assigns,
           @authorization_action,
           @authorization_category,
           "Test case not found: #{test_case_id}"
         ) do
      {:ok, _test_case, _project} -> apply_update(conn, test_case_id, attrs)
      {:error, message} -> EMCP.Tool.error(message)
    end
  end

  defp resolve_and_update(conn, %{"identifier" => identifier} = args, attrs) when is_binary(identifier) do
    with {:ok, {module_name, suite_name, name}} <- parse_identifier(identifier),
         {:ok, project} <-
           MCPTool.resolve_and_authorize_project(
             args,
             conn.assigns,
             @authorization_action,
             @authorization_category
           ),
         {:ok, test_case} <- find_test_case_by_name(project.id, module_name, suite_name, name) do
      apply_update(conn, test_case.id, attrs)
    else
      {:error, message} -> EMCP.Tool.error(message)
    end
  end

  defp resolve_and_update(_conn, _args, _attrs) do
    EMCP.Tool.error("Provide either test_case_id, or identifier with account_handle and project_handle.")
  end

  defp apply_update(conn, test_case_id, attrs) do
    actor_id = conn.assigns |> Authorization.authenticated_subject() |> subject_account_id()

    case Tests.update_test_case(test_case_id, attrs, actor_id: actor_id) do
      {:ok, updated} -> MCPTool.json_response(reply_payload(updated))
      {:error, :not_found} -> EMCP.Tool.error("Test case not found: #{test_case_id}")
    end
  end

  defp subject_account_id(%User{account: %{id: id}}), do: id
  defp subject_account_id(%Project{account: %{id: id}}), do: id
  defp subject_account_id(%AuthenticatedAccount{account: %{id: id}}), do: id
  defp subject_account_id(_), do: nil

  defp extract_update_attrs(args) do
    with {:ok, attrs} <- maybe_put_state(%{}, args),
         {:ok, attrs} <- maybe_put_is_flaky(attrs, args) do
      if map_size(attrs) == 0 do
        {:error, "Provide at least one of `state` or `is_flaky`."}
      else
        {:ok, attrs}
      end
    end
  end

  defp maybe_put_state(attrs, %{"state" => state}) when state in ["enabled", "muted"],
    do: {:ok, Map.put(attrs, :state, state)}

  defp maybe_put_state(_attrs, %{"state" => _invalid}), do: {:error, "`state` must be either `enabled` or `muted`."}
  defp maybe_put_state(attrs, _args), do: {:ok, attrs}

  defp maybe_put_is_flaky(attrs, %{"is_flaky" => is_flaky}) when is_boolean(is_flaky),
    do: {:ok, Map.put(attrs, :is_flaky, is_flaky)}

  defp maybe_put_is_flaky(_attrs, %{"is_flaky" => _invalid}), do: {:error, "`is_flaky` must be a boolean."}
  defp maybe_put_is_flaky(attrs, _args), do: {:ok, attrs}

  defp parse_identifier(identifier) do
    case String.split(identifier, "/") do
      [module_name, suite_name, name] -> {:ok, {module_name, suite_name, name}}
      [module_name, name] -> {:ok, {module_name, nil, name}}
      _ -> {:error, "Invalid identifier format. Use Module/Suite/TestCase or Module/TestCase."}
    end
  end

  defp find_test_case_by_name(project_id, module_name, suite_name, name) do
    filters =
      [
        %{field: :module_name, op: :==, value: module_name},
        %{field: :name, op: :==, value: name}
      ] ++ if(suite_name, do: [%{field: :suite_name, op: :==, value: suite_name}], else: [])

    {test_cases, _meta} =
      Tests.list_test_cases(project_id, %{
        filters: filters,
        page: 1,
        page_size: 1
      })

    case test_cases do
      [test_case | _] -> {:ok, test_case}
      [] -> {:error, "Test case not found: #{module_name}/#{suite_name || name}"}
    end
  end

  defp reply_payload(test_case) do
    %{
      id: test_case.id,
      name: test_case.name,
      module_name: test_case.module_name,
      suite_name: test_case.suite_name,
      is_flaky: test_case.is_flaky,
      state: test_case.state || "enabled"
    }
  end
end
