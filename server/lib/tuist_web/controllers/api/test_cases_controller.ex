defmodule TuistWeb.API.TestCasesController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Tests
  alias Tuist.Tests.Analytics
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata
  alias TuistWeb.API.Schemas.TestCase

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test)

  tags ["Test Cases"]

  operation(:index,
    summary: "List test cases associated with a given project.",
    operation_id: "listTestCases",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the account."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project."
      ],
      flaky: [
        in: :query,
        type: :boolean,
        description: "Filter by flaky status. When true, only returns flaky test cases."
      ],
      quarantined: [
        in: :query,
        type: :boolean,
        description: "Filter by quarantined status. When true, only returns quarantined test cases."
      ],
      module_name: [
        in: :query,
        type: :string,
        description: "Filter by module name. Returns only test cases in the given module."
      ],
      name: [
        in: :query,
        type: :string,
        description: "Filter by test case name."
      ],
      suite_name: [
        in: :query,
        type: :string,
        description: "Filter by suite name."
      ],
      state: [
        in: :query,
        type: %Schema{
          title: "TestCasesIndexState",
          type: :string,
          enum: ["enabled", "muted", "skipped"]
        },
        description: "Filter by test case state."
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "TestCasesIndexPageSize",
          description: "The maximum number of test cases to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 500
        }
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "TestCasesIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok:
        {"List of test cases", "application/json",
         %Schema{
           type: :object,
           properties: %{
             test_cases: %Schema{
               type: :array,
               items: TestCase
             },
             pagination_metadata: PaginationMetadata
           },
           required: [:test_cases, :pagination_metadata]
         }},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def index(
        %{assigns: %{selected_project: selected_project}, params: %{page_size: page_size, page: page} = params} = conn,
        _params
      ) do
    filters = build_filters(params)

    # `:id` is the unique tiebreaker for `:last_ran_at` so LIMIT/OFFSET pages
    # don't reshuffle tied rows between requests (which surfaces as duplicate
    # test cases across pages — see `tuist test case list --quarantined`).
    options = %{
      filters: filters,
      order_by: [:last_ran_at, :id],
      order_directions: [:desc, :asc],
      page: page,
      page_size: page_size
    }

    {test_cases, meta} = Tests.list_test_cases(selected_project.id, options)

    json(conn, %{
      test_cases:
        Enum.map(test_cases, fn test_case ->
          %{
            id: test_case.id,
            name: test_case.name,
            module: %{
              id: test_case.module_name,
              name: test_case.module_name
            },
            suite: build_suite(test_case.suite_name),
            avg_duration: test_case.avg_duration,
            is_flaky: test_case.is_flaky,
            is_quarantined: quarantined?(test_case.state),
            state: test_case.state || "enabled",
            url: ~p"/#{selected_project.account.name}/#{selected_project.name}/tests/test-cases/#{test_case.id}"
          }
        end),
      pagination_metadata: %{
        has_next_page: meta.has_next_page?,
        has_previous_page: meta.has_previous_page?,
        current_page: meta.current_page,
        page_size: meta.page_size,
        total_count: meta.total_count,
        total_pages: meta.total_pages
      }
    })
  end

  operation(:show,
    summary: "Get a test case by ID.",
    operation_id: "getTestCase",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the account."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project."
      ],
      test_case_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the test case."
      ]
    ],
    responses: %{
      ok:
        {"Test case details", "application/json",
         %Schema{
           type: :object,
           properties: %{
             id: %Schema{type: :string, format: :uuid, description: "The test case ID."},
             name: %Schema{type: :string, description: "Name of the test case."},
             module: %Schema{
               type: :object,
               required: [:id, :name],
               properties: %{
                 id: %Schema{type: :string, description: "ID of the module."},
                 name: %Schema{type: :string, description: "Name of the module."}
               }
             },
             suite: %Schema{
               type: :object,
               nullable: true,
               required: [:id, :name],
               properties: %{
                 id: %Schema{type: :string, description: "ID of the suite."},
                 name: %Schema{type: :string, description: "Name of the suite."}
               }
             },
             is_flaky: %Schema{type: :boolean, description: "Whether the test case is marked as flaky."},
             is_quarantined: %Schema{
               type: :boolean,
               deprecated: true,
               description:
                 "Whether the test case is quarantined (either `muted` or `skipped`). Deprecated: use `state` instead."
             },
             state: %Schema{
               type: :string,
               enum: ["enabled", "muted", "skipped"],
               description: "The state of the test case."
             },
             last_status: %Schema{
               type: :string,
               enum: ["success", "failure", "skipped"],
               description: "Status of the last run."
             },
             last_duration: %Schema{type: :integer, description: "Duration of the last run in milliseconds."},
             last_ran_at: %Schema{type: :integer, description: "Unix timestamp of when the test case last ran."},
             avg_duration: %Schema{type: :integer, description: "Average duration of recent runs in milliseconds."},
             reliability_rate: %Schema{type: :number, nullable: true, description: "Success rate percentage (0-100)."},
             flakiness_rate: %Schema{type: :number, description: "Flakiness rate percentage (0-100) over last 30 days."},
             total_runs: %Schema{type: :integer, description: "Total number of runs."},
             failed_runs: %Schema{type: :integer, description: "Number of failed runs."},
             url: %Schema{type: :string, description: "URL to view the test case in the dashboard."}
           },
           required: [
             :id,
             :name,
             :module,
             :is_flaky,
             :is_quarantined,
             :state,
             :last_status,
             :last_duration,
             :last_ran_at,
             :avg_duration,
             :flakiness_rate,
             :total_runs,
             :failed_runs,
             :url
           ]
         }},
      not_found: {"Test case not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def show(%{assigns: %{selected_project: selected_project}, params: %{test_case_id: test_case_id}} = conn, _params) do
    case Tests.get_test_case_by_id(test_case_id) do
      {:ok, test_case} ->
        if test_case.project_id == selected_project.id do
          default_branch = selected_project.default_branch || "main"
          analytics = Analytics.test_case_analytics_by_id(test_case_id)
          reliability_rate = Analytics.test_case_reliability_by_id(test_case_id, default_branch)
          flakiness_rate = Analytics.get_test_case_flakiness_rate(test_case)

          json(conn, %{
            id: test_case.id,
            name: test_case.name,
            module: %{
              id: test_case.module_name,
              name: test_case.module_name
            },
            suite: build_suite(test_case.suite_name),
            is_flaky: test_case.is_flaky,
            is_quarantined: quarantined?(test_case.state),
            state: test_case.state || "enabled",
            last_status: to_string(test_case.last_status),
            last_duration: test_case.last_duration,
            last_ran_at: test_case.last_ran_at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(),
            avg_duration: test_case.avg_duration,
            reliability_rate: reliability_rate,
            flakiness_rate: flakiness_rate,
            total_runs: analytics.total_count,
            failed_runs: analytics.failed_count,
            url: ~p"/#{selected_project.account.name}/#{selected_project.name}/tests/test-cases/#{test_case.id}"
          })
        else
          conn
          |> put_status(:not_found)
          |> json(%{message: "Test case not found."})
        end

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Test case not found."})
    end
  end

  operation(:events,
    summary: "List events for a test case.",
    operation_id: "listTestCaseEvents",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the account."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project."
      ],
      test_case_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the test case."
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "TestCaseEventsPageSize",
          description: "The maximum number of events to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 100
        }
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "TestCaseEventsPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok:
        {"List of test case events", "application/json",
         %Schema{
           type: :object,
           properties: %{
             events: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   event_type: %Schema{
                     type: :string,
                     enum: [
                       "first_run",
                       "marked_flaky",
                       "unmarked_flaky",
                       "quarantined",
                       "unquarantined",
                       "muted",
                       "unmuted",
                       "skipped",
                       "unskipped"
                     ],
                     description: "The type of event."
                   },
                   inserted_at: %Schema{type: :integer, description: "Unix timestamp of when the event occurred."},
                   actor: %Schema{
                     type: :object,
                     nullable: true,
                     description: "The user who triggered the event, or null for system events.",
                     properties: %{
                       id: %Schema{type: :integer, description: "The actor's account ID."},
                       name: %Schema{type: :string, description: "The actor's account handle."}
                     },
                     required: [:id, :name]
                   }
                 },
                 required: [:event_type, :inserted_at]
               }
             },
             pagination_metadata: PaginationMetadata
           },
           required: [:events, :pagination_metadata]
         }},
      not_found: {"Test case not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def events(
        %{assigns: %{selected_project: selected_project}, params: %{test_case_id: test_case_id} = params} = conn,
        _params
      ) do
    case Tests.get_test_case_by_id(test_case_id) do
      {:ok, test_case} ->
        if test_case.project_id == selected_project.id do
          page = Map.get(params, :page, 1)
          page_size = Map.get(params, :page_size, 20)

          {events, meta} = Tests.list_test_case_events(test_case_id, %{page: page, page_size: page_size})

          json(conn, %{
            events:
              Enum.map(events, fn event ->
                %{
                  event_type: event.event_type,
                  inserted_at:
                    event.inserted_at
                    |> NaiveDateTime.truncate(:second)
                    |> DateTime.from_naive!("Etc/UTC")
                    |> DateTime.to_unix(),
                  actor: build_actor(event.actor)
                }
              end),
            pagination_metadata: %{
              has_next_page: meta.has_next_page?,
              has_previous_page: meta.has_previous_page?,
              current_page: meta.current_page,
              page_size: meta.page_size,
              total_count: meta.total_count,
              total_pages: meta.total_pages
            }
          })
        else
          conn
          |> put_status(:not_found)
          |> json(%{message: "Test case not found."})
        end

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Test case not found."})
    end
  end

  defp build_actor(nil), do: nil
  defp build_actor(actor), do: %{id: actor.id, name: actor.name}

  defp build_filters(params) do
    []
    |> maybe_add_filter(:is_flaky, Map.get(params, :flaky))
    |> maybe_add_quarantined_filter(Map.get(params, :quarantined))
    |> maybe_add_filter(:module_name, Map.get(params, :module_name))
    |> maybe_add_filter(:name, Map.get(params, :name))
    |> maybe_add_filter(:suite_name, Map.get(params, :suite_name))
    |> maybe_add_filter(:state, Map.get(params, :state))
  end

  defp maybe_add_filter(filters, _field, nil), do: filters

  defp maybe_add_filter(filters, :is_flaky, true), do: filters ++ [%{field: :is_flaky, op: :==, value: true}]

  defp maybe_add_filter(filters, field, value), do: filters ++ [%{field: field, op: :==, value: value}]

  defp maybe_add_quarantined_filter(filters, nil), do: filters

  defp maybe_add_quarantined_filter(filters, true),
    do: filters ++ [%{field: :state, op: :in, value: ["muted", "skipped"]}]

  defp maybe_add_quarantined_filter(filters, false), do: filters ++ [%{field: :state, op: :==, value: "enabled"}]

  defp build_suite(nil), do: nil
  defp build_suite(""), do: nil
  defp build_suite(suite_name), do: %{id: suite_name, name: suite_name}

  defp quarantined?(state) when state in ["muted", "skipped"], do: true
  defp quarantined?(_), do: false
end
