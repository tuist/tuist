defmodule AtlasWeb.TimeOffControllerTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.TimeOffFixtures

  alias Atlas.TimeOff

  setup %{conn: conn} do
    {_conn, user} = log_in_user(conn)
    api = build_conn() |> put_req_header("authorization", "Bearer #{oauth_access_token_fixture(user)}")
    %{api: api, user: user, dates: %{starts_on: "2027-06-07", ends_on: "2027-06-11"}}
  end

  test "all personal endpoints require bearer authentication", %{conn: conn} do
    for method <- [:get, :post, :patch, :delete] do
      path = if method in [:patch, :delete], do: "/api/me/time-off/unknown", else: "/api/me/time-off"
      assert conn |> dispatch(@endpoint, method, path, %{}) |> json_response(401)
    end
  end

  test "owner can request, edit and cancel without assigning ownership or approving through parameters", %{
    api: api,
    user: user,
    dates: dates
  } do
    {_conn, other} = log_in_user(build_conn())
    response = post(api, ~p"/api/me/time-off", Map.merge(dates, %{user_id: other.id, status: "approved"}))
    assert %{"request" => %{"id" => id, "user_id" => owner, "status" => "pending"}} = json_response(response, 201)
    assert owner == user.id
    assert get_resp_header(response, "cache-control") == ["no-store"]

    assert %{"request" => %{"ends_on" => "2027-06-10"}} =
             api |> patch(~p"/api/me/time-off/#{id}", %{ends_on: "2027-06-10"}) |> json_response(200)

    assert %{"requests" => %{"items" => [%{"id" => ^id, "working_days" => 4}]}, "public_holidays" => %{}} =
             api |> get(~p"/api/me/time-off") |> json_response(200)

    assert %{"request" => %{"status" => "cancelled"}} = api |> delete(~p"/api/me/time-off/#{id}") |> json_response(200)
  end

  test "other users' requests cannot be read, changed or cancelled even by an executive", %{api: api, dates: dates} do
    other = user_fixture()
    {:ok, booking} = TimeOff.report_holiday(dates, other)

    assert %{"requests" => %{"items" => []}} =
             api |> get(~p"/api/me/time-off?user_id=#{other.id}") |> json_response(200)

    for method <- [:patch, :delete] do
      assert api |> dispatch(@endpoint, method, "/api/me/time-off/#{booking.id}", dates) |> json_response(404) == %{
               "error" => "time_off_request_unavailable"
             }
    end
  end

  test "invalid and overlapping ranges fail without inserting another request", %{api: api, dates: dates} do
    assert api |> post(~p"/api/me/time-off", dates) |> json_response(201)

    for attrs <- [
          dates,
          %{starts_on: "invalid", ends_on: "2027-06-11"},
          %{starts_on: "2027-06-11", ends_on: "2027-06-07"}
        ] do
      assert api |> post(~p"/api/me/time-off", attrs) |> json_response(422) == %{"error" => "invalid_time_off_dates"}
    end
  end

  test "editing approved requests requires approval again and history remains paginated", %{
    api: api,
    user: user,
    dates: dates
  } do
    {:ok, booking} = TimeOff.report_holiday(dates, user)
    {:ok, _} = TimeOff.review_holiday(booking.id, "approved", admin_fixture())

    assert %{"request" => %{"status" => "pending", "reviewed_by_id" => nil}} =
             api |> patch(~p"/api/me/time-off/#{booking.id}", %{ends_on: "2027-06-10"}) |> json_response(200)

    for index <- 1..10 do
      first = Date.add(~D[2028-01-01], index * 3)
      {:ok, _} = TimeOff.report_holiday(%{starts_on: first, ends_on: first}, user)
    end

    assert %{"requests" => %{"page" => 2, "total_pages" => 2, "items" => [_]}} =
             api |> get(~p"/api/me/time-off?requests_page=2") |> json_response(200)
  end
end
