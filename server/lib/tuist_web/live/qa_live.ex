defmodule TuistWeb.QALive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Terminal
  import TuistWeb.Previews.PlatformTag

  alias Tuist.AppBuilds.Preview
  alias Tuist.QA
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query
  alias TuistWeb.Utilities.SHA

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = "#{account.name}/#{project.name}"

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_qa", "QA")} · #{slug} · Tuist")
      |> assign(:qa_runs, [])
      |> assign(:qa_runs_meta, %{})
      |> assign(:available_apps, QA.available_apps_for_project(project.id))
      |> assign(:has_qa_runs, has_qa_runs?(project))
      |> load_qa_runs()

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    {
      :noreply,
      socket
      |> assign(:current_params, params)
      |> assign_analytics(params)
      |> load_qa_runs(params)
    }
  end

  def handle_event(
        "select_widget",
        %{"widget" => widget},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, uri: uri}} = socket
      ) do
    socket =
      push_patch(
        socket,
        to:
          "/#{selected_account.name}/#{selected_project.name}/qa?#{Query.put(uri.query, "analytics-selected-widget", widget)}",
        replace: true
      )

    {:noreply, socket}
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, uri: uri}} = socket
      ) do
    query_params =
      if preset == "custom" do
        uri.query
        |> Query.put("analytics-date-range", "custom")
        |> Query.put("analytics-start-date", start_date)
        |> Query.put("analytics-end-date", end_date)
      else
        Query.put(uri.query, "analytics-date-range", preset)
      end

    {:noreply, push_patch(socket, to: "/#{selected_account.name}/#{selected_project.name}/qa?#{query_params}")}
  end

  defp load_qa_runs(socket, params \\ %{}) do
    project = socket.assigns.selected_project

    options = %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }

    options =
      cond do
        not is_nil(Map.get(params, "before")) ->
          options
          |> Map.put(:last, 20)
          |> Map.put(:before, Map.get(params, "before"))

        not is_nil(Map.get(params, "after")) ->
          options
          |> Map.put(:first, 20)
          |> Map.put(:after, Map.get(params, "after"))

        true ->
          Map.put(options, :first, 20)
      end

    {qa_runs, qa_runs_meta} =
      QA.list_qa_runs_for_project(
        project,
        options,
        preload: [
          :run_steps,
          app_build: :preview
        ]
      )

    socket
    |> assign(:qa_runs, qa_runs)
    |> assign(:qa_runs_meta, qa_runs_meta)
  end

  defp assign_analytics(%{assigns: %{selected_project: project}} = socket, params) do
    analytics_app = params["analytics-app"] || "any"

    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "analytics")

    opts = [
      project_id: project.id,
      start_datetime: start_datetime,
      end_datetime: end_datetime,
      app_name:
        case analytics_app do
          "any" -> nil
          app_name -> app_name
        end
    ]

    uri = URI.new!("?" <> URI.encode_query(params))

    qa_runs_analytics = QA.qa_runs_analytics(project.id, opts)
    qa_issues_analytics = QA.qa_issues_analytics(project.id, opts)
    qa_duration_analytics = QA.qa_duration_analytics(project.id, opts)

    analytics_selected_widget = params["analytics-selected-widget"] || "qa_run_count"

    analytics_chart_data =
      case analytics_selected_widget do
        "qa_run_count" ->
          %{
            dates: qa_runs_analytics.dates,
            values: qa_runs_analytics.values,
            name: dgettext("dashboard_qa", "QA run count"),
            value_formatter: "{value}"
          }

        "qa_issues_count" ->
          %{
            dates: qa_issues_analytics.dates,
            values: qa_issues_analytics.values,
            name: dgettext("dashboard_qa", "App issues found"),
            value_formatter: "{value}"
          }

        "qa_duration" ->
          %{
            dates: qa_duration_analytics.dates,
            values:
              Enum.map(
                qa_duration_analytics.values,
                &((&1 / 1000) |> Decimal.from_float() |> Decimal.round(1))
              ),
            name: dgettext("dashboard_qa", "Avg. QA duration"),
            value_formatter: "fn:formatSeconds"
          }
      end

    socket
    |> assign(:analytics_preset, preset)
    |> assign(:analytics_period, period)
    |> assign(:analytics_trend_label, analytics_trend_label(preset))
    |> assign(:analytics_app, analytics_app)
    |> assign(:analytics_app_label, analytics_app_label(analytics_app, socket.assigns.available_apps))
    |> assign(:analytics_selected_widget, analytics_selected_widget)
    |> assign(:qa_runs_analytics, qa_runs_analytics)
    |> assign(:qa_issues_analytics, qa_issues_analytics)
    |> assign(:qa_duration_analytics, qa_duration_analytics)
    |> assign(:analytics_chart_data, analytics_chart_data)
    |> assign(:uri, uri)
  end

  defp analytics_trend_label("last-24-hours"), do: dgettext("dashboard_qa", "since yesterday")
  defp analytics_trend_label("last-7-days"), do: dgettext("dashboard_qa", "since last week")
  defp analytics_trend_label("last-12-months"), do: dgettext("dashboard_qa", "since last year")
  defp analytics_trend_label("custom"), do: dgettext("dashboard_qa", "since last period")
  defp analytics_trend_label(_), do: dgettext("dashboard_qa", "since last month")

  defp analytics_app_label("any", _available_apps), do: dgettext("dashboard_qa", "Any")

  defp analytics_app_label(app_name, available_apps) when is_binary(app_name) do
    case Enum.find(available_apps, fn {bundle_id, _display_name} -> bundle_id == app_name end) do
      {_bundle_id, display_name} -> display_name
      nil -> app_name
    end
  end

  defp analytics_app_label(_app_name, _available_apps), do: dgettext("dashboard_qa", "Any")

  defp has_qa_runs?(project) do
    project
    |> QA.list_qa_runs_for_project(%{
      first: 1,
      order_by: [:inserted_at],
      order_directions: [:desc]
    })
    |> case do
      {[], _meta} -> false
      {_runs, _meta} -> true
    end
  end

  def empty_state_light_background(assigns) do
    ~H"""
    <svg
      width="1184"
      height="1045"
      viewBox="0 0 1184 1045"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <mask
        id="mask0_4492_129052"
        style="mask-type:alpha"
        maskUnits="userSpaceOnUse"
        x="0"
        y="0"
        width="1184"
        height="1045"
      >
        <rect width="1184" height="1045" fill="url(#paint0_radial_4492_129052)" fill-opacity="0.4" />
        <rect width="1184" height="1045" fill="url(#paint1_radial_4492_129052)" fill-opacity="0.4" />
        <rect width="1184" height="1045" fill="url(#paint2_radial_4492_129052)" fill-opacity="0.4" />
        <rect width="1184" height="1045" fill="url(#paint3_radial_4492_129052)" fill-opacity="0.4" />
      </mask>
      <g mask="url(#mask0_4492_129052)">
        <g filter="url(#filter0_dddd_4492_129052)">
          <rect
            opacity="0.3"
            x="473.996"
            y="72.0625"
            width="204.979"
            height="414.838"
            rx="35.1392"
            fill="#B3BAC1"
          />
          <rect x="479.059" y="77.1445" width="194.631" height="404.491" rx="31.3465" fill="#FDFDFD" />
          <rect x="547.145" y="82.6953" width="58.8905" height="17.9432" rx="8.9716" fill="#BFC5CA" />
          <path
            d="M492.656 146.426C492.656 143.708 494.86 141.504 497.579 141.504H655.099C657.818 141.504 660.022 143.708 660.022 146.426C660.022 149.145 657.818 151.349 655.099 151.349H497.579C494.86 151.349 492.656 149.145 492.656 146.426Z"
            fill="#E6E8EA"
          />
          <path
            d="M492.656 166.114C492.656 163.395 494.86 161.191 497.579 161.191H655.099C657.818 161.191 660.022 163.395 660.022 166.114C660.022 168.833 657.818 171.036 655.099 171.036H497.579C494.86 171.036 492.656 168.833 492.656 166.114Z"
            fill="#E6E8EA"
          />
          <path
            d="M492.656 190.724C492.656 185.287 497.064 180.879 502.501 180.879H650.176C655.614 180.879 660.022 185.287 660.022 190.724V220.259C660.022 225.696 655.614 230.104 650.176 230.104H502.501C497.064 230.104 492.656 225.696 492.656 220.259V190.724Z"
            fill="#E6E8EA"
          />
          <path
            d="M492.656 244.872C492.656 242.153 494.86 239.949 497.579 239.949H546.804C549.522 239.949 551.726 242.153 551.726 244.872C551.726 247.59 549.522 249.794 546.804 249.794H497.579C494.86 249.794 492.656 247.59 492.656 244.872Z"
            fill="#E6E8EA"
          />
          <path
            d="M492.656 427.005C492.656 421.568 497.064 417.16 502.501 417.16H650.176C655.614 417.16 660.022 421.568 660.022 427.005C660.022 432.442 655.614 436.85 650.176 436.85H502.501C497.064 436.85 492.656 432.442 492.656 427.005Z"
            fill="#E6E8EA"
          />
        </g>
        <g filter="url(#filter1_dddd_4492_129052)">
          <g filter="url(#filter2_i_4492_129052)">
            <rect
              x="673.031"
              y="178.969"
              width="14.8499"
              height="32.4841"
              transform="rotate(-22.362 673.031 178.969)"
              fill="#B2B2B2"
            />
          </g>
          <g filter="url(#filter3_ii_4492_129052)">
            <rect
              x="677.266"
              y="206.332"
              width="27.8435"
              height="105.805"
              rx="13.9217"
              transform="rotate(-22.362 677.266 206.332)"
              fill="#D7D9DB"
            />
          </g>
          <g filter="url(#filter4_ii_4492_129052)">
            <circle
              cx="651.047"
              cy="107.211"
              r="76.0389"
              transform="rotate(-22.362 651.047 107.211)"
              stroke="url(#paint4_linear_4492_129052)"
              stroke-width="12.1988"
            />
          </g>
          <g filter="url(#filter5_i_4492_129052)">
            <g clip-path="url(#clip0_4492_129052)">
              <rect
                x="588.398"
                y="44.5781"
                width="125.296"
                height="125.296"
                rx="62.6479"
                fill="white"
              />
              <g filter="url(#filter6_dddd_4492_129052)">
                <rect
                  opacity="0.3"
                  x="425.949"
                  y="71.0352"
                  width="299.057"
                  height="605.235"
                  rx="51.2669"
                  fill="#B3BAC1"
                />
                <rect
                  x="433.34"
                  y="78.4414"
                  width="283.961"
                  height="590.14"
                  rx="45.7336"
                  fill="#FDFDFD"
                />
                <rect
                  x="532.672"
                  y="86.5352"
                  width="85.9194"
                  height="26.1786"
                  rx="13.0893"
                  fill="#BFC5CA"
                />
                <g filter="url(#filter7_f_4492_129052)" />
              </g>
              <path
                d="M677.707 54.7534C664.212 48.8489 649.05 47.9696 634.963 52.2748C620.877 56.5799 608.796 65.7851 600.908 78.2247L612.747 85.7316C618.842 76.1198 628.176 69.0071 639.06 65.6806C649.945 62.354 661.66 63.0334 672.087 67.5958L677.707 54.7534Z"
                fill="url(#paint5_linear_4492_129052)"
                fill-opacity="0.2"
              />
            </g>
            <rect
              x="584.061"
              y="40.2404"
              width="133.971"
              height="133.971"
              rx="66.9856"
              stroke="#F0F0F0"
              stroke-width="8.67544"
            />
          </g>
        </g>
        <g filter="url(#filter8_ddd_4492_129052)">
          <path
            d="M619 397.158C619 392.54 622.744 388.797 627.362 388.797H748.604C753.222 388.797 756.966 392.54 756.966 397.158V422.243C756.966 426.861 753.222 430.605 748.604 430.605H627.362C622.744 430.605 619 426.861 619 422.243V397.158Z"
            fill="#FDFDFD"
          />
          <path
            d="M627.363 401.341C627.363 399.032 629.235 397.16 631.544 397.16H744.425C746.734 397.16 748.606 399.032 748.606 401.341V418.064C748.606 420.373 746.734 422.245 744.425 422.245H631.544C629.235 422.245 627.363 420.373 627.363 418.064V401.341Z"
            fill="#F1F2F4"
          />
        </g>
        <g filter="url(#filter9_ddd_4492_129052)">
          <path
            d="M440.711 324.053C440.711 319.435 444.455 315.691 449.073 315.691H492.971C497.589 315.691 501.332 319.435 501.332 324.053V349.138C501.332 353.756 497.589 357.499 492.971 357.499H449.073C444.455 357.499 440.711 353.756 440.711 349.138V324.053Z"
            fill="#FDFDFD"
          />
          <path
            d="M449.074 328.235C449.074 325.926 450.946 324.055 453.255 324.055H488.792C491.101 324.055 492.972 325.926 492.972 328.235V344.959C492.972 347.268 491.101 349.139 488.792 349.139H453.255C450.946 349.139 449.074 347.268 449.074 344.959V328.235Z"
            fill="#F1F2F4"
          />
        </g>
        <g filter="url(#filter10_ddd_4492_129052)">
          <path
            d="M378 232.053C378 227.435 381.744 223.691 386.362 223.691H595.401C600.019 223.691 603.762 227.435 603.762 232.053V257.138C603.762 261.756 600.019 265.499 595.401 265.499H386.362C381.744 265.499 378 261.756 378 257.138V232.053Z"
            fill="#FDFDFD"
          />
          <path
            d="M386.363 236.235C386.363 233.926 388.235 232.055 390.544 232.055H591.222C593.531 232.055 595.403 233.926 595.403 236.235V252.959C595.403 255.268 593.531 257.139 591.222 257.139H390.544C388.235 257.139 386.363 255.268 386.363 252.959V236.235Z"
            fill="#F1F2F4"
          />
        </g>
      </g>
      <defs>
        <filter
          id="filter0_dddd_4492_129052"
          x="451.042"
          y="66.077"
          width="251.111"
          height="489.816"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="2.09039" />
          <feGaussianBlur stdDeviation="3.13559" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.06 0" />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_4492_129052" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="12.5424" />
          <feGaussianBlur stdDeviation="6.27118" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.05 0" />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_4492_129052"
            result="effect2_dropShadow_4492_129052"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="27.1751" />
          <feGaussianBlur stdDeviation="8.36157" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.03 0" />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_4492_129052"
            result="effect3_dropShadow_4492_129052"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="48.079" />
          <feGaussianBlur stdDeviation="9.40677" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.01 0" />
          <feBlend
            mode="normal"
            in2="effect3_dropShadow_4492_129052"
            result="effect4_dropShadow_4492_129052"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect4_dropShadow_4492_129052"
            result="shape"
          />
        </filter>
        <filter
          id="filter1_dddd_4492_129052"
          x="487.395"
          y="-10.452"
          width="374.975"
          height="537.246"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="8.36157" />
          <feGaussianBlur stdDeviation="9.40677" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.08 0" />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_4492_129052" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="35.5367" />
          <feGaussianBlur stdDeviation="17.7683" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.07 0" />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_4492_129052"
            result="effect2_dropShadow_4492_129052"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="79.4349" />
          <feGaussianBlur stdDeviation="24.0395" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.04 0" />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_4492_129052"
            result="effect3_dropShadow_4492_129052"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="140.056" />
          <feGaussianBlur stdDeviation="28.2203" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.01 0" />
          <feBlend
            mode="normal"
            in2="effect3_dropShadow_4492_129052"
            result="effect4_dropShadow_4492_129052"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect4_dropShadow_4492_129052"
            result="shape"
          />
        </filter>
        <filter
          id="filter2_i_4492_129052"
          x="673.031"
          y="169.14"
          width="26.0938"
          height="39.8722"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feBlend mode="normal" in="SourceGraphic" in2="BackgroundImageFix" result="shape" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="-4.18079" />
          <feGaussianBlur stdDeviation="2.09039" />
          <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.12 0" />
          <feBlend mode="normal" in2="shape" result="effect1_innerShadow_4492_129052" />
        </filter>
        <filter
          id="filter3_ii_4492_129052"
          x="681.512"
          y="195.804"
          width="57.5117"
          height="108.311"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feBlend mode="normal" in="SourceGraphic" in2="BackgroundImageFix" result="shape" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="4.18079" />
          <feGaussianBlur stdDeviation="2.09039" />
          <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
          <feColorMatrix type="matrix" values="0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 0 0 0 0.25 0" />
          <feBlend mode="normal" in2="shape" result="effect1_innerShadow_4492_129052" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="-4.18079" />
          <feGaussianBlur stdDeviation="2.09039" />
          <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.547495 0 0 0 0 0.547495 0 0 0 0 0.547495 0 0 0 0.25 0"
          />
          <feBlend
            mode="normal"
            in2="effect1_innerShadow_4492_129052"
            result="effect2_innerShadow_4492_129052"
          />
        </filter>
        <filter
          id="filter4_ii_4492_129052"
          x="568.887"
          y="20.87"
          width="164.32"
          height="172.682"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feBlend mode="normal" in="SourceGraphic" in2="BackgroundImageFix" result="shape" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="4.18079" />
          <feGaussianBlur stdDeviation="2.09039" />
          <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
          <feColorMatrix type="matrix" values="0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 0 0 0 0.25 0" />
          <feBlend mode="normal" in2="shape" result="effect1_innerShadow_4492_129052" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="-4.18079" />
          <feGaussianBlur stdDeviation="2.09039" />
          <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.335543 0 0 0 0 0.335543 0 0 0 0 0.335543 0 0 0 0.25 0"
          />
          <feBlend
            mode="normal"
            in2="effect1_innerShadow_4492_129052"
            result="effect2_innerShadow_4492_129052"
          />
        </filter>
        <filter
          id="filter5_i_4492_129052"
          x="579.723"
          y="35.9023"
          width="142.648"
          height="146.361"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feBlend mode="normal" in="SourceGraphic" in2="BackgroundImageFix" result="shape" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="3.71247" />
          <feGaussianBlur stdDeviation="9.28117" />
          <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.1915 0 0 0 0 0.188022 0 0 0 0 0.188022 0 0 0 0.12 0"
          />
          <feBlend mode="normal" in2="shape" result="effect1_innerShadow_4492_129052" />
        </filter>
        <filter
          id="filter6_dddd_4492_129052"
          x="353.384"
          y="56.295"
          width="444.521"
          height="852.842"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="9.07172" />
          <feGaussianBlur stdDeviation="10.5837" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.09 0" />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_4492_129052" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="42.3347" />
          <feGaussianBlur stdDeviation="21.1674" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.08 0" />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_4492_129052"
            result="effect2_dropShadow_4492_129052"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="93.7412" />
          <feGaussianBlur stdDeviation="27.2152" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.05 0" />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_4492_129052"
            result="effect3_dropShadow_4492_129052"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="163.291" />
          <feGaussianBlur stdDeviation="33.263" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.01 0" />
          <feBlend
            mode="normal"
            in2="effect3_dropShadow_4492_129052"
            result="effect4_dropShadow_4492_129052"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect4_dropShadow_4492_129052"
            result="shape"
          />
        </filter>
        <filter
          id="filter7_f_4492_129052"
          x="438.808"
          y="157.984"
          width="272.907"
          height="459.633"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feBlend mode="normal" in="SourceGraphic" in2="BackgroundImageFix" result="shape" />
          <feGaussianBlur stdDeviation="7.18178" result="effect1_foregroundBlur_4492_129052" />
        </filter>
        <filter
          id="filter8_ddd_4492_129052"
          x="616.91"
          y="386.706"
          width="142.146"
          height="48.0798"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="2.09039" />
          <feGaussianBlur stdDeviation="1.0452" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.180392 0 0 0 0 0.2 0 0 0 0 0.219608 0 0 0 0.1 0"
          />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_4492_129052" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feMorphology
            radius="2.09039"
            operator="dilate"
            in="SourceAlpha"
            result="effect2_dropShadow_4492_129052"
          />
          <feOffset />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix type="matrix" values="0 0 0 0 0.18 0 0 0 0 0.2 0 0 0 0 0.22 0 0 0 0.08 0" />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_4492_129052"
            result="effect2_dropShadow_4492_129052"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="2.09039" />
          <feGaussianBlur stdDeviation="1.0452" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.0862745 0 0 0 0 0.0941176 0 0 0 0 0.109804 0 0 0 0.05 0"
          />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_4492_129052"
            result="effect3_dropShadow_4492_129052"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect3_dropShadow_4492_129052"
            result="shape"
          />
        </filter>
        <filter
          id="filter9_ddd_4492_129052"
          x="438.621"
          y="313.601"
          width="64.8019"
          height="48.0798"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="2.09039" />
          <feGaussianBlur stdDeviation="1.0452" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.180392 0 0 0 0 0.2 0 0 0 0 0.219608 0 0 0 0.1 0"
          />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_4492_129052" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feMorphology
            radius="2.09039"
            operator="dilate"
            in="SourceAlpha"
            result="effect2_dropShadow_4492_129052"
          />
          <feOffset />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix type="matrix" values="0 0 0 0 0.18 0 0 0 0 0.2 0 0 0 0 0.22 0 0 0 0.08 0" />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_4492_129052"
            result="effect2_dropShadow_4492_129052"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="2.09039" />
          <feGaussianBlur stdDeviation="1.0452" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.0862745 0 0 0 0 0.0941176 0 0 0 0 0.109804 0 0 0 0.05 0"
          />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_4492_129052"
            result="effect3_dropShadow_4492_129052"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect3_dropShadow_4492_129052"
            result="shape"
          />
        </filter>
        <filter
          id="filter10_ddd_4492_129052"
          x="375.91"
          y="221.601"
          width="229.943"
          height="48.0798"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="2.09039" />
          <feGaussianBlur stdDeviation="1.0452" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.180392 0 0 0 0 0.2 0 0 0 0 0.219608 0 0 0 0.1 0"
          />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_4492_129052" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feMorphology
            radius="2.09039"
            operator="dilate"
            in="SourceAlpha"
            result="effect2_dropShadow_4492_129052"
          />
          <feOffset />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix type="matrix" values="0 0 0 0 0.18 0 0 0 0 0.2 0 0 0 0 0.22 0 0 0 0.08 0" />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_4492_129052"
            result="effect2_dropShadow_4492_129052"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="2.09039" />
          <feGaussianBlur stdDeviation="1.0452" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.0862745 0 0 0 0 0.0941176 0 0 0 0 0.109804 0 0 0 0.05 0"
          />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_4492_129052"
            result="effect3_dropShadow_4492_129052"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect3_dropShadow_4492_129052"
            result="shape"
          />
        </filter>
        <radialGradient
          id="paint0_radial_4492_129052"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(883 292) rotate(-43.8958) scale(458.644 519.65)"
        >
          <stop stop-color="#E51C01" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint1_radial_4492_129052"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(411.5 627.5) rotate(134.109) scale(591.213 669.853)"
        >
          <stop stop-color="#FFC300" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint2_radial_4492_129052"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(725 628.5) rotate(39.3184) scale(557.109 631.212)"
        >
          <stop stop-color="#F44277" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint3_radial_4492_129052"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(339.5 441) rotate(-129.32) scale(535.79 607.057)"
        >
          <stop stop-color="#8366FF" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
        <linearGradient
          id="paint4_linear_4492_129052"
          x1="603.066"
          y1="42.9645"
          x2="651.047"
          y2="189.35"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="#E8E8E8" />
          <stop offset="0.468611" stop-color="#D9DBDD" />
        </linearGradient>
        <linearGradient
          id="paint5_linear_4492_129052"
          x1="652.987"
          y1="49.582"
          x2="650.896"
          y2="121.701"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="#EBEBEB" />
          <stop offset="1" stop-color="#858585" />
        </linearGradient>
        <clipPath id="clip0_4492_129052">
          <rect x="588.398" y="44.5781" width="125.296" height="125.296" rx="62.6479" fill="white" />
        </clipPath>
      </defs>
    </svg>
    """
  end

  def empty_state_dark_background(assigns) do
    ~H"""
    <svg
      width="1184"
      height="1045"
      viewBox="0 0 1184 1045"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <mask
        id="mask0_4494_130196"
        style="mask-type:alpha"
        maskUnits="userSpaceOnUse"
        x="0"
        y="0"
        width="1184"
        height="1045"
      >
        <rect width="1184" height="1045" fill="url(#paint0_radial_4494_130196)" fill-opacity="0.4" />
        <rect width="1184" height="1045" fill="url(#paint1_radial_4494_130196)" fill-opacity="0.4" />
        <rect width="1184" height="1045" fill="url(#paint2_radial_4494_130196)" fill-opacity="0.4" />
        <rect width="1184" height="1045" fill="url(#paint3_radial_4494_130196)" fill-opacity="0.4" />
      </mask>
      <g mask="url(#mask0_4494_130196)">
        <g filter="url(#filter0_dddd_4494_130196)">
          <rect
            opacity="0.3"
            x="473.996"
            y="72.0625"
            width="204.979"
            height="414.838"
            rx="35.1392"
            fill="#A4A4A4"
          />
          <rect x="479.059" y="77.1445" width="194.631" height="404.491" rx="31.3465" fill="#181818" />
          <rect x="547.145" y="82.6953" width="58.8905" height="17.9432" rx="8.9716" fill="#3A3A3A" />
          <path
            d="M492.656 146.426C492.656 143.708 494.86 141.504 497.579 141.504H655.099C657.818 141.504 660.022 143.708 660.022 146.426C660.022 149.145 657.818 151.349 655.099 151.349H497.579C494.86 151.349 492.656 149.145 492.656 146.426Z"
            fill="#585858"
          />
          <path
            d="M492.656 166.114C492.656 163.395 494.86 161.191 497.579 161.191H655.099C657.818 161.191 660.022 163.395 660.022 166.114C660.022 168.833 657.818 171.036 655.099 171.036H497.579C494.86 171.036 492.656 168.833 492.656 166.114Z"
            fill="#585858"
          />
          <path
            d="M492.656 190.724C492.656 185.287 497.064 180.879 502.501 180.879H650.176C655.614 180.879 660.022 185.287 660.022 190.724V220.259C660.022 225.696 655.614 230.104 650.176 230.104H502.501C497.064 230.104 492.656 225.696 492.656 220.259V190.724Z"
            fill="#585858"
          />
          <path
            d="M492.656 244.872C492.656 242.153 494.86 239.949 497.579 239.949H546.804C549.522 239.949 551.726 242.153 551.726 244.872C551.726 247.59 549.522 249.794 546.804 249.794H497.579C494.86 249.794 492.656 247.59 492.656 244.872Z"
            fill="#B3BAC1"
          />
          <path
            d="M492.656 427.005C492.656 421.568 497.064 417.16 502.501 417.16H650.176C655.614 417.16 660.022 421.568 660.022 427.005C660.022 432.442 655.614 436.85 650.176 436.85H502.501C497.064 436.85 492.656 432.442 492.656 427.005Z"
            fill="#585858"
          />
        </g>
        <g filter="url(#filter1_dddd_4494_130196)">
          <g filter="url(#filter2_i_4494_130196)">
            <rect
              x="673.031"
              y="178.969"
              width="14.8499"
              height="32.4841"
              transform="rotate(-22.362 673.031 178.969)"
              fill="#2E2E2E"
            />
          </g>
          <g filter="url(#filter3_ii_4494_130196)">
            <rect
              x="677.266"
              y="206.332"
              width="27.8435"
              height="105.805"
              rx="13.9217"
              transform="rotate(-22.362 677.266 206.332)"
              fill="#292929"
            />
          </g>
          <g filter="url(#filter4_ii_4494_130196)">
            <circle
              cx="651.047"
              cy="107.211"
              r="76.0389"
              transform="rotate(-22.362 651.047 107.211)"
              stroke="url(#paint4_linear_4494_130196)"
              stroke-width="12.1988"
            />
          </g>
          <g filter="url(#filter5_i_4494_130196)">
            <g clip-path="url(#clip0_4494_130196)">
              <rect
                x="588.398"
                y="44.5781"
                width="125.296"
                height="125.296"
                rx="62.6479"
                fill="#2C2C2C"
              />
              <g filter="url(#filter6_dddd_4494_130196)">
                <rect
                  opacity="0.3"
                  x="425.949"
                  y="71.0352"
                  width="299.057"
                  height="605.235"
                  rx="51.2669"
                  fill="#A4A4A4"
                />
                <rect
                  x="433.34"
                  y="78.4414"
                  width="283.961"
                  height="590.14"
                  rx="45.7336"
                  fill="#181818"
                />
                <rect
                  x="532.672"
                  y="86.5352"
                  width="85.9194"
                  height="26.1786"
                  rx="13.0893"
                  fill="#3A3A3A"
                />
                <g filter="url(#filter7_f_4494_130196)" />
              </g>
              <path
                d="M677.707 54.7534C664.212 48.8489 649.05 47.9696 634.963 52.2748C620.877 56.5799 608.796 65.7851 600.908 78.2247L612.747 85.7316C618.842 76.1198 628.176 69.0071 639.06 65.6806C649.945 62.354 661.66 63.0334 672.087 67.5958L677.707 54.7534Z"
                fill="url(#paint5_linear_4494_130196)"
                fill-opacity="0.2"
              />
            </g>
            <rect
              x="584.061"
              y="40.2404"
              width="133.971"
              height="133.971"
              rx="66.9856"
              stroke="#222222"
              stroke-width="8.67544"
            />
          </g>
        </g>
        <g filter="url(#filter8_ddd_4494_130196)">
          <path
            d="M619 397.158C619 392.54 622.744 388.797 627.362 388.797H748.604C753.222 388.797 756.966 392.54 756.966 397.158V422.243C756.966 426.861 753.222 430.605 748.604 430.605H627.362C622.744 430.605 619 426.861 619 422.243V397.158Z"
            fill="#0E0E0E"
          />
          <path
            d="M627.363 401.341C627.363 399.032 629.235 397.16 631.544 397.16H744.425C746.734 397.16 748.606 399.032 748.606 401.341V418.064C748.606 420.373 746.734 422.245 744.425 422.245H631.544C629.235 422.245 627.363 420.373 627.363 418.064V401.341Z"
            fill="#181818"
          />
        </g>
        <g filter="url(#filter9_ddd_4494_130196)">
          <path
            d="M440.711 324.053C440.711 319.435 444.455 315.691 449.073 315.691H492.971C497.589 315.691 501.332 319.435 501.332 324.053V349.138C501.332 353.756 497.589 357.499 492.971 357.499H449.073C444.455 357.499 440.711 353.756 440.711 349.138V324.053Z"
            fill="#0E0E0E"
          />
          <path
            d="M449.074 328.235C449.074 325.926 450.946 324.055 453.255 324.055H488.792C491.101 324.055 492.972 325.926 492.972 328.235V344.959C492.972 347.268 491.101 349.139 488.792 349.139H453.255C450.946 349.139 449.074 347.268 449.074 344.959V328.235Z"
            fill="#181818"
          />
        </g>
        <g filter="url(#filter10_ddd_4494_130196)">
          <path
            d="M378 232.053C378 227.435 381.744 223.691 386.362 223.691H595.401C600.019 223.691 603.762 227.435 603.762 232.053V257.138C603.762 261.756 600.019 265.499 595.401 265.499H386.362C381.744 265.499 378 261.756 378 257.138V232.053Z"
            fill="#0E0E0E"
          />
          <path
            d="M386.363 236.235C386.363 233.926 388.235 232.055 390.544 232.055H591.222C593.531 232.055 595.403 233.926 595.403 236.235V252.959C595.403 255.268 593.531 257.139 591.222 257.139H390.544C388.235 257.139 386.363 255.268 386.363 252.959V236.235Z"
            fill="#181818"
          />
        </g>
      </g>
      <defs>
        <filter
          id="filter0_dddd_4494_130196"
          x="451.042"
          y="66.077"
          width="251.111"
          height="489.816"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="2.09039" />
          <feGaussianBlur stdDeviation="3.13559" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.06 0" />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_4494_130196" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="12.5424" />
          <feGaussianBlur stdDeviation="6.27118" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.05 0" />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_4494_130196"
            result="effect2_dropShadow_4494_130196"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="27.1751" />
          <feGaussianBlur stdDeviation="8.36157" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.03 0" />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_4494_130196"
            result="effect3_dropShadow_4494_130196"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="48.079" />
          <feGaussianBlur stdDeviation="9.40677" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.01 0" />
          <feBlend
            mode="normal"
            in2="effect3_dropShadow_4494_130196"
            result="effect4_dropShadow_4494_130196"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect4_dropShadow_4494_130196"
            result="shape"
          />
        </filter>
        <filter
          id="filter1_dddd_4494_130196"
          x="487.395"
          y="-10.452"
          width="374.975"
          height="537.246"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="8.36157" />
          <feGaussianBlur stdDeviation="9.40677" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.08 0" />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_4494_130196" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="35.5367" />
          <feGaussianBlur stdDeviation="17.7683" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.07 0" />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_4494_130196"
            result="effect2_dropShadow_4494_130196"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="79.4349" />
          <feGaussianBlur stdDeviation="24.0395" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.04 0" />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_4494_130196"
            result="effect3_dropShadow_4494_130196"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="140.056" />
          <feGaussianBlur stdDeviation="28.2203" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.01 0" />
          <feBlend
            mode="normal"
            in2="effect3_dropShadow_4494_130196"
            result="effect4_dropShadow_4494_130196"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect4_dropShadow_4494_130196"
            result="shape"
          />
        </filter>
        <filter
          id="filter2_i_4494_130196"
          x="673.031"
          y="169.14"
          width="26.0938"
          height="39.8722"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feBlend mode="normal" in="SourceGraphic" in2="BackgroundImageFix" result="shape" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="-4.18079" />
          <feGaussianBlur stdDeviation="2.09039" />
          <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.12 0" />
          <feBlend mode="normal" in2="shape" result="effect1_innerShadow_4494_130196" />
        </filter>
        <filter
          id="filter3_ii_4494_130196"
          x="681.512"
          y="195.804"
          width="57.5117"
          height="108.311"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feBlend mode="normal" in="SourceGraphic" in2="BackgroundImageFix" result="shape" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="4.18079" />
          <feGaussianBlur stdDeviation="2.09039" />
          <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.531513 0 0 0 0 0.531513 0 0 0 0 0.531513 0 0 0 0.25 0"
          />
          <feBlend mode="normal" in2="shape" result="effect1_innerShadow_4494_130196" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="-4.18079" />
          <feGaussianBlur stdDeviation="2.09039" />
          <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.402907 0 0 0 0 0.402794 0 0 0 0 0.402794 0 0 0 0.25 0"
          />
          <feBlend
            mode="normal"
            in2="effect1_innerShadow_4494_130196"
            result="effect2_innerShadow_4494_130196"
          />
        </filter>
        <filter
          id="filter4_ii_4494_130196"
          x="568.887"
          y="20.87"
          width="164.32"
          height="172.682"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feBlend mode="normal" in="SourceGraphic" in2="BackgroundImageFix" result="shape" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="4.18079" />
          <feGaussianBlur stdDeviation="2.09039" />
          <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
          <feColorMatrix type="matrix" values="0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 0 0 0 0.25 0" />
          <feBlend mode="normal" in2="shape" result="effect1_innerShadow_4494_130196" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="-4.18079" />
          <feGaussianBlur stdDeviation="2.09039" />
          <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.335543 0 0 0 0 0.335543 0 0 0 0 0.335543 0 0 0 0.25 0"
          />
          <feBlend
            mode="normal"
            in2="effect1_innerShadow_4494_130196"
            result="effect2_innerShadow_4494_130196"
          />
        </filter>
        <filter
          id="filter5_i_4494_130196"
          x="579.723"
          y="35.9023"
          width="142.648"
          height="146.361"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feBlend mode="normal" in="SourceGraphic" in2="BackgroundImageFix" result="shape" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="3.71247" />
          <feGaussianBlur stdDeviation="9.28117" />
          <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.1915 0 0 0 0 0.188022 0 0 0 0 0.188022 0 0 0 0.12 0"
          />
          <feBlend mode="normal" in2="shape" result="effect1_innerShadow_4494_130196" />
        </filter>
        <filter
          id="filter6_dddd_4494_130196"
          x="353.384"
          y="56.295"
          width="444.521"
          height="852.842"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="9.07172" />
          <feGaussianBlur stdDeviation="10.5837" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.09 0" />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_4494_130196" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="42.3347" />
          <feGaussianBlur stdDeviation="21.1674" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.08 0" />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_4494_130196"
            result="effect2_dropShadow_4494_130196"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="93.7412" />
          <feGaussianBlur stdDeviation="27.2152" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.05 0" />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_4494_130196"
            result="effect3_dropShadow_4494_130196"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="163.291" />
          <feGaussianBlur stdDeviation="33.263" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.01 0" />
          <feBlend
            mode="normal"
            in2="effect3_dropShadow_4494_130196"
            result="effect4_dropShadow_4494_130196"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect4_dropShadow_4494_130196"
            result="shape"
          />
        </filter>
        <filter
          id="filter7_f_4494_130196"
          x="438.808"
          y="157.984"
          width="272.907"
          height="459.633"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feBlend mode="normal" in="SourceGraphic" in2="BackgroundImageFix" result="shape" />
          <feGaussianBlur stdDeviation="7.18178" result="effect1_foregroundBlur_4494_130196" />
        </filter>
        <filter
          id="filter8_ddd_4494_130196"
          x="616.91"
          y="386.706"
          width="142.146"
          height="48.0798"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="2.09039" />
          <feGaussianBlur stdDeviation="1.0452" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.180392 0 0 0 0 0.2 0 0 0 0 0.219608 0 0 0 0.1 0"
          />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_4494_130196" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feMorphology
            radius="2.09039"
            operator="dilate"
            in="SourceAlpha"
            result="effect2_dropShadow_4494_130196"
          />
          <feOffset />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix type="matrix" values="0 0 0 0 0.18 0 0 0 0 0.2 0 0 0 0 0.22 0 0 0 0.08 0" />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_4494_130196"
            result="effect2_dropShadow_4494_130196"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="2.09039" />
          <feGaussianBlur stdDeviation="1.0452" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.0862745 0 0 0 0 0.0941176 0 0 0 0 0.109804 0 0 0 0.05 0"
          />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_4494_130196"
            result="effect3_dropShadow_4494_130196"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect3_dropShadow_4494_130196"
            result="shape"
          />
        </filter>
        <filter
          id="filter9_ddd_4494_130196"
          x="438.621"
          y="313.601"
          width="64.8011"
          height="48.0786"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="2.09" />
          <feGaussianBlur stdDeviation="1.045" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.3 0" />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_4494_130196" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feMorphology
            radius="2.09"
            operator="dilate"
            in="SourceAlpha"
            result="effect2_dropShadow_4494_130196"
          />
          <feOffset />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.411765 0 0 0 0 0.423529 0 0 0 0 0.447059 0 0 0 0.45 0"
          />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_4494_130196"
            result="effect2_dropShadow_4494_130196"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="2.09" />
          <feGaussianBlur stdDeviation="1.045" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.0862745 0 0 0 0 0.0941176 0 0 0 0 0.109804 0 0 0 0.3 0"
          />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_4494_130196"
            result="effect3_dropShadow_4494_130196"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect3_dropShadow_4494_130196"
            result="shape"
          />
        </filter>
        <filter
          id="filter10_ddd_4494_130196"
          x="375.91"
          y="221.601"
          width="229.942"
          height="48.0786"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="2.09" />
          <feGaussianBlur stdDeviation="1.045" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.3 0" />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_4494_130196" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feMorphology
            radius="2.09"
            operator="dilate"
            in="SourceAlpha"
            result="effect2_dropShadow_4494_130196"
          />
          <feOffset />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.411765 0 0 0 0 0.423529 0 0 0 0 0.447059 0 0 0 0.45 0"
          />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_4494_130196"
            result="effect2_dropShadow_4494_130196"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="2.09" />
          <feGaussianBlur stdDeviation="1.045" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.0862745 0 0 0 0 0.0941176 0 0 0 0 0.109804 0 0 0 0.3 0"
          />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_4494_130196"
            result="effect3_dropShadow_4494_130196"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect3_dropShadow_4494_130196"
            result="shape"
          />
        </filter>
        <radialGradient
          id="paint0_radial_4494_130196"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(883 292) rotate(-43.8958) scale(458.644 519.65)"
        >
          <stop stop-color="#E51C01" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint1_radial_4494_130196"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(411.5 627.5) rotate(134.109) scale(591.213 669.853)"
        >
          <stop stop-color="#FFC300" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint2_radial_4494_130196"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(725 628.5) rotate(39.3184) scale(557.109 631.212)"
        >
          <stop stop-color="#F44277" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint3_radial_4494_130196"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(339.5 441) rotate(-129.32) scale(535.79 607.057)"
        >
          <stop stop-color="#8366FF" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
        <linearGradient
          id="paint4_linear_4494_130196"
          x1="603.066"
          y1="42.9645"
          x2="651.047"
          y2="189.35"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="#373737" />
          <stop offset="0.468611" stop-color="#292929" />
        </linearGradient>
        <linearGradient
          id="paint5_linear_4494_130196"
          x1="652.987"
          y1="49.582"
          x2="650.896"
          y2="121.701"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="#EBEBEB" />
          <stop offset="1" stop-color="#858585" />
        </linearGradient>
        <clipPath id="clip0_4494_130196">
          <rect x="588.398" y="44.5781" width="125.296" height="125.296" rx="62.6479" fill="white" />
        </clipPath>
      </defs>
    </svg>
    """
  end
end
