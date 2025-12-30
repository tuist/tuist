defmodule TuistWeb.PreviewsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.Filter
  import TuistWeb.EmptyState
  import TuistWeb.Previews.AppPreview
  import TuistWeb.Previews.PlatformTag
  import TuistWeb.Previews.RanByBadge
  import TuistWeb.Previews.RunButton

  alias Noora.Filter
  alias Tuist.AppBuilds
  alias Tuist.Projects
  alias TuistWeb.Utilities.Query
  alias TuistWeb.Utilities.SHA

  def mount(_params, _session, %{assigns: %{selected_project: project}} = socket) do
    {:ok,
     socket
     |> assign(
       :head_title,
       "#{dgettext("dashboard_previews", "Previews")} · #{Projects.get_project_slug_from_id(project.id)} · Tuist"
     )
     |> assign(
       :latest_app_previews,
       AppBuilds.latest_previews_with_distinct_bundle_ids(project)
     )
     |> assign(
       :user_agent,
       UAParser.parse(get_connect_info(socket, :user_agent))
     )
     |> assign(:available_filters, define_filters())}
  end

  def handle_params(params, _uri, %{assigns: %{selected_project: project, available_filters: available_filters}} = socket) do
    uri = URI.new!("?" <> URI.encode_query(params))
    filters = Filter.Operations.decode_filters_from_query(params, available_filters)
    filter_name = params["name"] || ""

    {next_previews, next_previews_meta} = assign_previews(project, filters, params)

    {
      :noreply,
      socket
      |> assign(:uri, uri)
      |> assign(:active_filters, filters)
      |> assign(:filter_name, filter_name)
      |> assign(:previews, next_previews)
      |> assign(:previews_meta, next_previews_meta)
      |> assign(
        :latest_app_previews,
        AppBuilds.latest_previews_with_distinct_bundle_ids(project)
      )
    }
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      filter_id
      |> Filter.Operations.add_filter_to_query(socket)
      |> Query.clear_cursors()

    {:noreply,
     socket
     |> push_patch(
       to:
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/previews?#{updated_params}"
     )
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_query_params =
      params
      |> Filter.Operations.update_filters_in_query(socket)
      |> Query.clear_cursors()

    {:noreply,
     socket
     |> push_patch(
       to:
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/previews?#{updated_query_params}"
     )
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  def handle_event(
        "search-name",
        %{"name" => name},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, uri: uri}} = socket
      ) do
    query =
      uri.query
      |> Query.put("name", name)
      |> Query.drop("after")
      |> Query.drop("before")

    socket =
      push_patch(
        socket,
        to: "/#{selected_account.name}/#{selected_project.name}/previews?#{query}",
        replace: true
      )

    {:noreply, socket}
  end

  defp assign_previews(project, filters, params) do
    base_flop_filters = [%{field: :project_id, op: :==, value: project.id}]
    filter_flop_filters = build_flop_filters(filters)

    name_filter =
      case params["name"] do
        nil -> []
        "" -> []
        name -> [%{field: :display_name, op: :ilike_and, value: name}]
      end

    flop_filters = base_flop_filters ++ filter_flop_filters ++ name_filter

    options = %{
      filters: flop_filters,
      order_by: [:inserted_at],
      order_directions: [:desc]
    }

    options =
      cond do
        !is_nil(params["after"]) ->
          options
          |> Map.put(:first, 20)
          |> Map.put(:after, params["after"])

        !is_nil(params["before"]) ->
          options
          |> Map.put(:last, 20)
          |> Map.put(:before, params["before"])

        true ->
          Map.put(options, :first, 20)
      end

    AppBuilds.list_previews(options, preload: [:created_by_account, :app_builds, project: :account])
  end

  defp build_flop_filters(filters) do
    filters
    |> Enum.filter(fn filter -> not is_nil(filter.value) and filter.value != "" end)
    |> Enum.map(fn filter ->
      %{field: filter.field, op: :ilike_and, value: filter.value}
    end)
  end

  defp define_filters do
    [
      %Filter.Filter{
        id: "track",
        field: :track,
        display_name: dgettext("dashboard_previews", "Track"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "branch",
        field: :git_branch,
        display_name: dgettext("dashboard_previews", "Branch"),
        type: :text,
        operator: :=~,
        value: ""
      }
    ]
  end

  defp format_track(track) when track in [nil, ""], do: dgettext("dashboard_previews", "None")
  defp format_track(track), do: String.capitalize(track)

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
        id="mask0_1434_54215"
        style="mask-type:alpha"
        maskUnits="userSpaceOnUse"
        x="0"
        y="0"
        width="1184"
        height="1045"
      >
        <rect width="1184" height="1045" fill="url(#paint0_radial_1434_54215)" fill-opacity="0.4" />
        <rect width="1184" height="1045" fill="url(#paint1_radial_1434_54215)" fill-opacity="0.4" />
        <rect width="1184" height="1045" fill="url(#paint2_radial_1434_54215)" fill-opacity="0.4" />
        <rect width="1184" height="1045" fill="url(#paint3_radial_1434_54215)" fill-opacity="0.4" />
      </mask>
      <g mask="url(#mask0_1434_54215)">
        <path
          d="M929 173V287.5H786"
          stroke="#C7CCD1"
          stroke-linejoin="round"
          stroke-dasharray="10 10"
        />
        <path
          d="M268 172V286.5H411"
          stroke="#C7CCD1"
          stroke-linejoin="round"
          stroke-dasharray="10 10"
        />
        <path
          d="M478.5 721.501C478.224 721.501 478 721.725 478 722.001C478 722.277 478.224 722.501 478.5 722.501V721.501ZM710 761.5C710.276 761.5 710.5 761.276 710.5 761C710.5 760.724 710.276 760.5 710 760.5V761.5ZM592.5 835V835.5C592.776 835.5 593 835.276 593 835H592.5ZM559.5 835V834.5C559.224 834.5 559 834.724 559 835H559.5ZM559 882.5C559 882.776 559.224 883 559.5 883C559.776 883 560 882.776 560 882.5H559ZM592 326.013C592 326.289 592.224 326.513 592.5 326.513C592.776 326.513 593 326.289 593 326.013H592ZM593 336.038C593 335.761 592.776 335.538 592.5 335.538C592.224 335.538 592 335.761 592 336.038H593ZM592 346.063C592 346.339 592.224 346.563 592.5 346.563C592.776 346.563 593 346.339 593 346.063H592ZM593 356.088C593 355.811 592.776 355.588 592.5 355.588C592.224 355.588 592 355.811 592 356.088H593ZM592 366.113C592 366.389 592.224 366.613 592.5 366.613C592.776 366.613 593 366.389 593 366.113H592ZM593 376.138C593 375.862 592.776 375.638 592.5 375.638C592.224 375.638 592 375.862 592 376.138H593ZM592 386.163C592 386.439 592.224 386.663 592.5 386.663C592.776 386.663 593 386.439 593 386.163H592ZM593 396.188C593 395.912 592.776 395.688 592.5 395.688C592.224 395.688 592 395.912 592 396.188H593ZM592 406.213C592 406.489 592.224 406.713 592.5 406.713C592.776 406.713 593 406.489 593 406.213H592ZM593 416.238C593 415.962 592.776 415.738 592.5 415.738C592.224 415.738 592 415.962 592 416.238H593ZM592 426.263C592 426.539 592.224 426.763 592.5 426.763C592.776 426.763 593 426.539 593 426.263H592ZM593 436.288C593 436.012 592.776 435.788 592.5 435.788C592.224 435.788 592 436.012 592 436.288H593ZM592 446.313C592 446.589 592.224 446.813 592.5 446.813C592.776 446.813 593 446.589 593 446.313H592ZM593 456.338C593 456.062 592.776 455.838 592.5 455.838C592.224 455.838 592 456.062 592 456.338H593ZM592 466.363C592 466.639 592.224 466.863 592.5 466.863C592.776 466.863 593 466.639 593 466.363H592ZM593 476.388C593 476.112 592.776 475.888 592.5 475.888C592.224 475.888 592 476.112 592 476.388H593ZM592 486.413C592 486.689 592.224 486.913 592.5 486.913C592.776 486.913 593 486.689 593 486.413H592ZM593 496.438C593 496.162 592.776 495.938 592.5 495.938C592.224 495.938 592 496.162 592 496.438H593ZM592 506.463C592 506.739 592.224 506.963 592.5 506.963C592.776 506.963 593 506.739 593 506.463H592ZM593 516.488C593 516.212 592.776 515.988 592.5 515.988C592.224 515.988 592 516.212 592 516.488H593ZM592 526.513C592 526.789 592.224 527.013 592.5 527.013C592.776 527.013 593 526.789 593 526.513H592ZM593 536.538C593 536.262 592.776 536.038 592.5 536.038C592.224 536.038 592 536.262 592 536.538H593ZM592 546.563C592 546.839 592.224 547.063 592.5 547.063C592.776 547.063 593 546.839 593 546.563H592ZM593 556.588C593 556.312 592.776 556.088 592.5 556.088C592.224 556.088 592 556.312 592 556.588H593ZM592 566.613C592 566.889 592.224 567.113 592.5 567.113C592.776 567.113 593 566.889 593 566.613H592ZM593 576.638C593 576.362 592.776 576.138 592.5 576.138C592.224 576.138 592 576.362 592 576.638H593ZM592 586.663C592 586.939 592.224 587.163 592.5 587.163C592.776 587.163 593 586.939 593 586.663H592ZM593 596.688C593 596.412 592.776 596.188 592.5 596.188C592.224 596.188 592 596.412 592 596.688H593ZM592 606.713C592 606.989 592.224 607.213 592.5 607.213C592.776 607.213 593 606.989 593 606.713H592ZM593 616.738C593 616.462 592.776 616.238 592.5 616.238C592.224 616.238 592 616.462 592 616.738H593ZM592 626.763C592 627.039 592.224 627.263 592.5 627.263C592.776 627.263 593 627.039 593 626.763H592ZM593 636.788C593 636.512 592.776 636.288 592.5 636.288C592.224 636.288 592 636.512 592 636.788H593ZM592 646.813C592 647.09 592.224 647.313 592.5 647.313C592.776 647.313 593 647.09 593 646.813H592ZM593 656.838C593 656.562 592.776 656.338 592.5 656.338C592.224 656.338 592 656.562 592 656.838H593ZM592 666.863C592 667.14 592.224 667.363 592.5 667.363C592.776 667.363 593 667.14 593 666.863H592ZM593 676.888C593 676.612 592.776 676.388 592.5 676.388C592.224 676.388 592 676.612 592 676.888H593ZM592 686.913C592 687.19 592.224 687.413 592.5 687.413C592.776 687.413 593 687.19 593 686.913H592ZM593 696.939C593 696.662 592.776 696.439 592.5 696.439C592.224 696.439 592 696.662 592 696.939H593ZM592 706.964C592 707.24 592.224 707.464 592.5 707.464C592.776 707.464 593 707.24 593 706.964H592ZM593 716.989C593 716.712 592.776 716.489 592.5 716.489C592.224 716.489 592 716.712 592 716.989H593ZM483.25 722.501C483.526 722.501 483.75 722.277 483.75 722.001C483.75 721.725 483.526 721.501 483.25 721.501V722.501ZM492.75 721.501C492.474 721.501 492.25 721.725 492.25 722.001C492.25 722.277 492.474 722.501 492.75 722.501V721.501ZM502.25 722.501C502.526 722.501 502.75 722.277 502.75 722.001C502.75 721.725 502.526 721.501 502.25 721.501V722.501ZM511.75 721.501C511.474 721.501 511.25 721.725 511.25 722.001C511.25 722.277 511.474 722.501 511.75 722.501V721.501ZM521.25 722.501C521.526 722.501 521.75 722.277 521.75 722.001C521.75 721.725 521.526 721.501 521.25 721.501V722.501ZM530.75 721.501C530.474 721.501 530.25 721.725 530.25 722.001C530.25 722.277 530.474 722.501 530.75 722.501V721.501ZM540.25 722.501C540.526 722.501 540.75 722.277 540.75 722.001C540.75 721.725 540.526 721.501 540.25 721.501V722.501ZM549.75 721.501C549.474 721.501 549.25 721.725 549.25 722.001C549.25 722.277 549.474 722.501 549.75 722.501V721.501ZM559.25 722.501C559.526 722.501 559.75 722.277 559.75 722.001C559.75 721.725 559.526 721.501 559.25 721.501V722.501ZM568.75 721.501C568.474 721.501 568.25 721.725 568.25 722.001C568.25 722.277 568.474 722.501 568.75 722.501V721.501ZM578.25 722.501C578.526 722.501 578.75 722.277 578.75 722.001C578.75 721.725 578.526 721.501 578.25 721.501V722.501ZM587.75 721.501C587.474 721.501 587.25 721.725 587.25 722.001C587.25 722.277 587.474 722.501 587.75 722.501V721.501ZM592 726.876C592 727.152 592.224 727.376 592.5 727.376C592.776 727.376 593 727.152 593 726.876H592ZM593 736.626C593 736.35 592.776 736.126 592.5 736.126C592.224 736.126 592 736.35 592 736.626H593ZM592 746.375C592 746.652 592.224 746.875 592.5 746.875C592.776 746.875 593 746.652 593 746.375H592ZM593 756.125C593 755.849 592.776 755.625 592.5 755.625C592.224 755.625 592 755.849 592 756.125H593ZM597.396 761.5C597.672 761.5 597.896 761.276 597.896 761C597.896 760.724 597.672 760.5 597.396 760.5V761.5ZM607.188 760.5C606.911 760.5 606.688 760.724 606.688 761C606.688 761.276 606.911 761.5 607.188 761.5V760.5ZM616.979 761.5C617.255 761.5 617.479 761.276 617.479 761C617.479 760.724 617.255 760.5 616.979 760.5V761.5ZM626.771 760.5C626.495 760.5 626.271 760.724 626.271 761C626.271 761.276 626.495 761.5 626.771 761.5V760.5ZM636.562 761.5C636.839 761.5 637.062 761.276 637.062 761C637.062 760.724 636.839 760.5 636.562 760.5V761.5ZM646.354 760.5C646.078 760.5 645.854 760.724 645.854 761C645.854 761.276 646.078 761.5 646.354 761.5V760.5ZM656.146 761.5C656.422 761.5 656.646 761.276 656.646 761C656.646 760.724 656.422 760.5 656.146 760.5V761.5ZM665.938 760.5C665.661 760.5 665.438 760.724 665.438 761C665.438 761.276 665.661 761.5 665.938 761.5V760.5ZM675.729 761.5C676.005 761.5 676.229 761.276 676.229 761C676.229 760.724 676.005 760.5 675.729 760.5V761.5ZM685.521 760.5C685.245 760.5 685.021 760.724 685.021 761C685.021 761.276 685.245 761.5 685.521 761.5V760.5ZM695.312 761.5C695.589 761.5 695.812 761.276 695.812 761C695.812 760.724 695.589 760.5 695.312 760.5V761.5ZM705.104 760.5C704.828 760.5 704.604 760.724 704.604 761C704.604 761.276 704.828 761.5 705.104 761.5V760.5ZM560 876.562C560 876.286 559.776 876.062 559.5 876.062C559.224 876.062 559 876.286 559 876.562H560ZM559 864.688C559 864.964 559.224 865.188 559.5 865.188C559.776 865.188 560 864.964 560 864.688H559ZM560 852.812C560 852.536 559.776 852.312 559.5 852.312C559.224 852.312 559 852.536 559 852.812H560ZM559 840.938C559 841.214 559.224 841.438 559.5 841.438C559.776 841.438 560 841.214 560 840.938H559ZM563.625 835.5C563.901 835.5 564.125 835.276 564.125 835C564.125 834.724 563.901 834.5 563.625 834.5V835.5ZM571.875 834.5C571.599 834.5 571.375 834.724 571.375 835C571.375 835.276 571.599 835.5 571.875 835.5V834.5ZM580.125 835.5C580.401 835.5 580.625 835.276 580.625 835C580.625 834.724 580.401 834.5 580.125 834.5V835.5ZM588.375 834.5C588.099 834.5 587.875 834.724 587.875 835C587.875 835.276 588.099 835.5 588.375 835.5V834.5ZM593 830.375C593 830.099 592.776 829.875 592.5 829.875C592.224 829.875 592 830.099 592 830.375H593ZM592 821.125C592 821.401 592.224 821.625 592.5 821.625C592.776 821.625 593 821.401 593 821.125H592ZM593 811.875C593 811.599 592.776 811.375 592.5 811.375C592.224 811.375 592 811.599 592 811.875H593ZM592 802.625C592 802.901 592.224 803.125 592.5 803.125C592.776 803.125 593 802.901 593 802.625H592ZM593 793.375C593 793.099 592.776 792.875 592.5 792.875C592.224 792.875 592 793.099 592 793.375H593ZM592 784.125C592 784.401 592.224 784.625 592.5 784.625C592.776 784.625 593 784.401 593 784.125H592ZM593 774.875C593 774.599 592.776 774.375 592.5 774.375C592.224 774.375 592 774.599 592 774.875H593ZM592 765.625C592 765.901 592.224 766.125 592.5 766.125C592.776 766.125 593 765.901 593 765.625H592ZM592 321V326.013H593V321H592ZM592 336.038V346.063H593V336.038H592ZM592 356.088V366.113H593V356.088H592ZM592 376.138V386.163H593V376.138H592ZM592 396.188V406.213H593V396.188H592ZM592 416.238V426.263H593V416.238H592ZM592 436.288V446.313H593V436.288H592ZM592 456.338V466.363H593V456.338H592ZM592 476.388V486.413H593V476.388H592ZM592 496.438V506.463H593V496.438H592ZM592 516.488V526.513H593V516.488H592ZM592 536.538V546.563H593V536.538H592ZM592 556.588V566.613H593V556.588H592ZM592 576.638V586.663H593V576.638H592ZM592 596.688V606.713H593V596.688H592ZM592 616.738V626.763H593V616.738H592ZM592 636.788V646.813H593V636.788H592ZM592 656.838V666.863H593V656.838H592ZM592 676.888V686.913H593V676.888H592ZM592 696.939V706.964H593V696.939H592ZM592 716.989V722.001H593V716.989H592ZM478.5 722.501H483.25V721.501H478.5V722.501ZM492.75 722.501H502.25V721.501H492.75V722.501ZM511.75 722.501H521.25V721.501H511.75V722.501ZM530.75 722.501H540.25V721.501H530.75V722.501ZM549.75 722.501H559.25V721.501H549.75V722.501ZM568.75 722.501H578.25V721.501H568.75V722.501ZM587.75 722.501H592.5V721.501H587.75V722.501ZM592 722.001V726.876H593V722.001H592ZM592 736.626V746.375H593V736.626H592ZM592 756.125V761H593V756.125H592ZM592.5 761.5H597.396V760.5H592.5V761.5ZM607.188 761.5H616.979V760.5H607.188V761.5ZM626.771 761.5H636.562V760.5H626.771V761.5ZM646.354 761.5H656.146V760.5H646.354V761.5ZM665.938 761.5H675.729V760.5H665.938V761.5ZM685.521 761.5H695.312V760.5H685.521V761.5ZM705.104 761.5H710V760.5H705.104V761.5ZM560 882.5V876.562H559V882.5H560ZM560 864.688V852.812H559V864.688H560ZM560 840.938V835H559V840.938H560ZM559.5 835.5H563.625V834.5H559.5V835.5ZM571.875 835.5H580.125V834.5H571.875V835.5ZM588.375 835.5H592.5V834.5H588.375V835.5ZM593 835V830.375H592V835H593ZM593 821.125V811.875H592V821.125H593ZM593 802.625V793.375H592V802.625H593ZM593 784.125V774.875H592V784.125H593ZM593 765.625V761H592V765.625H593Z"
          fill="#C7CCD1"
        />
        <g filter="url(#filter0_ddd_1434_54215)">
          <path
            d="M86 112C86 105.373 91.3726 100 98 100H449C455.627 100 461 105.373 461 112V160C461 166.627 455.627 172 449 172H98C91.3726 172 86 166.627 86 160V112Z"
            fill="#FDFDFD"
          />
          <rect x="98" y="112" width="48" height="48" rx="6" fill="#F1F2F4" />
          <rect x="162" y="112" width="242" height="20" rx="6" fill="#F1F2F4" />
          <rect x="166" y="146" width="12" height="12" rx="6" fill="#F1F2F4" />
          <rect x="180" y="146" width="17" height="12" rx="6" fill="#F1F2F4" />
          <rect x="214" y="146" width="12" height="12" rx="6" fill="#F1F2F4" />
          <rect x="228" y="146" width="39" height="12" rx="6" fill="#F1F2F4" />
          <rect x="420" y="124" width="24" height="24" rx="6" fill="#F1F2F4" />
        </g>
        <g filter="url(#filter1_ddd_1434_54215)">
          <path
            d="M411 261C411 254.373 416.373 249 423 249H774C780.627 249 786 254.373 786 261V309C786 315.627 780.627 321 774 321H423C416.373 321 411 315.627 411 309V261Z"
            fill="#FDFDFD"
          />
          <rect x="423" y="261" width="48" height="48" rx="6" fill="#F1F2F4" />
          <rect x="487" y="261" width="242" height="20" rx="6" fill="#F1F2F4" />
          <rect x="491" y="295" width="12" height="12" rx="6" fill="#F1F2F4" />
          <rect x="505" y="295" width="17" height="12" rx="6" fill="#F1F2F4" />
          <rect x="539" y="295" width="12" height="12" rx="6" fill="#F1F2F4" />
          <rect x="553" y="295" width="39" height="12" rx="6" fill="#F1F2F4" />
          <rect x="745" y="273" width="24" height="24" rx="6" fill="#F1F2F4" />
        </g>
        <g filter="url(#filter2_ddd_1434_54215)">
          <path
            d="M722 102C722 95.3726 727.373 90 734 90H1085C1091.63 90 1097 95.3726 1097 102V150C1097 156.627 1091.63 162 1085 162H734C727.373 162 722 156.627 722 150V102Z"
            fill="#FDFDFD"
          />
          <rect x="734" y="102" width="48" height="48" rx="6" fill="#F1F2F4" />
          <rect x="798" y="102" width="242" height="20" rx="6" fill="#F1F2F4" />
          <rect x="802" y="136" width="12" height="12" rx="6" fill="#F1F2F4" />
          <rect x="816" y="136" width="17" height="12" rx="6" fill="#F1F2F4" />
          <rect x="850" y="136" width="12" height="12" rx="6" fill="#F1F2F4" />
          <rect x="864" y="136" width="39" height="12" rx="6" fill="#F1F2F4" />
          <rect x="1056" y="114" width="24" height="24" rx="6" fill="#F1F2F4" />
        </g>
        <g filter="url(#filter3_ddd_1434_54215)">
          <path
            d="M710 738C710 731.373 715.373 726 722 726H1073C1079.63 726 1085 731.373 1085 738V786C1085 792.627 1079.63 798 1073 798H722C715.373 798 710 792.627 710 786V738Z"
            fill="#FDFDFD"
          />
          <rect x="722" y="738" width="48" height="48" rx="6" fill="#F1F2F4" />
          <rect x="786" y="738" width="242" height="20" rx="6" fill="#F1F2F4" />
          <rect x="790" y="772" width="12" height="12" rx="6" fill="#F1F2F4" />
          <rect x="804" y="772" width="17" height="12" rx="6" fill="#F1F2F4" />
          <rect x="838" y="772" width="12" height="12" rx="6" fill="#F1F2F4" />
          <rect x="852" y="772" width="39" height="12" rx="6" fill="#F1F2F4" />
          <rect x="1044" y="750" width="24" height="24" rx="6" fill="#F1F2F4" />
        </g>
        <g filter="url(#filter4_ddd_1434_54215)">
          <path
            d="M103 698C103 691.373 108.373 686 115 686H466C472.627 686 478 691.373 478 698V746C478 752.627 472.627 758 466 758H115C108.373 758 103 752.627 103 746V698Z"
            fill="#FDFDFD"
          />
          <rect x="115" y="698" width="48" height="48" rx="6" fill="#F1F2F4" />
          <rect x="179" y="698" width="242" height="20" rx="6" fill="#F1F2F4" />
          <rect x="183" y="732" width="12" height="12" rx="6" fill="#F1F2F4" />
          <rect x="197" y="732" width="17" height="12" rx="6" fill="#F1F2F4" />
          <rect x="231" y="732" width="12" height="12" rx="6" fill="#F1F2F4" />
          <rect x="245" y="732" width="39" height="12" rx="6" fill="#F1F2F4" />
          <rect x="437" y="710" width="24" height="24" rx="6" fill="#F1F2F4" />
        </g>
        <g filter="url(#filter5_ddd_1434_54215)">
          <path
            d="M359 895C359 888.373 364.373 883 371 883H722C728.627 883 734 888.373 734 895V943C734 949.627 728.627 955 722 955H371C364.373 955 359 949.627 359 943V895Z"
            fill="#FDFDFD"
          />
          <rect x="371" y="895" width="48" height="48" rx="6" fill="#F1F2F4" />
          <rect x="435" y="895" width="242" height="20" rx="6" fill="#F1F2F4" />
          <rect x="439" y="929" width="12" height="12" rx="6" fill="#F1F2F4" />
          <rect x="453" y="929" width="17" height="12" rx="6" fill="#F1F2F4" />
          <rect x="487" y="929" width="12" height="12" rx="6" fill="#F1F2F4" />
          <rect x="501" y="929" width="39" height="12" rx="6" fill="#F1F2F4" />
          <rect x="693" y="907" width="24" height="24" rx="6" fill="#F1F2F4" />
        </g>
      </g>
      <defs>
        <filter
          id="filter0_ddd_1434_54215"
          x="85"
          y="99"
          width="377"
          height="75"
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
          <feOffset dy="1" />
          <feGaussianBlur stdDeviation="0.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.180392 0 0 0 0 0.2 0 0 0 0 0.219608 0 0 0 0.1 0"
          />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_1434_54215" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feMorphology
            radius="1"
            operator="dilate"
            in="SourceAlpha"
            result="effect2_dropShadow_1434_54215"
          />
          <feOffset />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix type="matrix" values="0 0 0 0 0.18 0 0 0 0 0.2 0 0 0 0 0.22 0 0 0 0.08 0" />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_1434_54215"
            result="effect2_dropShadow_1434_54215"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="1" />
          <feGaussianBlur stdDeviation="0.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.0862745 0 0 0 0 0.0941176 0 0 0 0 0.109804 0 0 0 0.05 0"
          />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_1434_54215"
            result="effect3_dropShadow_1434_54215"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect3_dropShadow_1434_54215"
            result="shape"
          />
        </filter>
        <filter
          id="filter1_ddd_1434_54215"
          x="410"
          y="248"
          width="377"
          height="75"
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
          <feOffset dy="1" />
          <feGaussianBlur stdDeviation="0.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.180392 0 0 0 0 0.2 0 0 0 0 0.219608 0 0 0 0.1 0"
          />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_1434_54215" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feMorphology
            radius="1"
            operator="dilate"
            in="SourceAlpha"
            result="effect2_dropShadow_1434_54215"
          />
          <feOffset />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix type="matrix" values="0 0 0 0 0.18 0 0 0 0 0.2 0 0 0 0 0.22 0 0 0 0.08 0" />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_1434_54215"
            result="effect2_dropShadow_1434_54215"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="1" />
          <feGaussianBlur stdDeviation="0.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.0862745 0 0 0 0 0.0941176 0 0 0 0 0.109804 0 0 0 0.05 0"
          />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_1434_54215"
            result="effect3_dropShadow_1434_54215"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect3_dropShadow_1434_54215"
            result="shape"
          />
        </filter>
        <filter
          id="filter2_ddd_1434_54215"
          x="721"
          y="89"
          width="377"
          height="75"
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
          <feOffset dy="1" />
          <feGaussianBlur stdDeviation="0.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.180392 0 0 0 0 0.2 0 0 0 0 0.219608 0 0 0 0.1 0"
          />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_1434_54215" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feMorphology
            radius="1"
            operator="dilate"
            in="SourceAlpha"
            result="effect2_dropShadow_1434_54215"
          />
          <feOffset />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix type="matrix" values="0 0 0 0 0.18 0 0 0 0 0.2 0 0 0 0 0.22 0 0 0 0.08 0" />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_1434_54215"
            result="effect2_dropShadow_1434_54215"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="1" />
          <feGaussianBlur stdDeviation="0.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.0862745 0 0 0 0 0.0941176 0 0 0 0 0.109804 0 0 0 0.05 0"
          />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_1434_54215"
            result="effect3_dropShadow_1434_54215"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect3_dropShadow_1434_54215"
            result="shape"
          />
        </filter>
        <filter
          id="filter3_ddd_1434_54215"
          x="709"
          y="725"
          width="377"
          height="75"
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
          <feOffset dy="1" />
          <feGaussianBlur stdDeviation="0.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.180392 0 0 0 0 0.2 0 0 0 0 0.219608 0 0 0 0.1 0"
          />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_1434_54215" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feMorphology
            radius="1"
            operator="dilate"
            in="SourceAlpha"
            result="effect2_dropShadow_1434_54215"
          />
          <feOffset />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix type="matrix" values="0 0 0 0 0.18 0 0 0 0 0.2 0 0 0 0 0.22 0 0 0 0.08 0" />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_1434_54215"
            result="effect2_dropShadow_1434_54215"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="1" />
          <feGaussianBlur stdDeviation="0.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.0862745 0 0 0 0 0.0941176 0 0 0 0 0.109804 0 0 0 0.05 0"
          />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_1434_54215"
            result="effect3_dropShadow_1434_54215"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect3_dropShadow_1434_54215"
            result="shape"
          />
        </filter>
        <filter
          id="filter4_ddd_1434_54215"
          x="102"
          y="685"
          width="377"
          height="75"
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
          <feOffset dy="1" />
          <feGaussianBlur stdDeviation="0.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.180392 0 0 0 0 0.2 0 0 0 0 0.219608 0 0 0 0.1 0"
          />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_1434_54215" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feMorphology
            radius="1"
            operator="dilate"
            in="SourceAlpha"
            result="effect2_dropShadow_1434_54215"
          />
          <feOffset />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix type="matrix" values="0 0 0 0 0.18 0 0 0 0 0.2 0 0 0 0 0.22 0 0 0 0.08 0" />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_1434_54215"
            result="effect2_dropShadow_1434_54215"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="1" />
          <feGaussianBlur stdDeviation="0.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.0862745 0 0 0 0 0.0941176 0 0 0 0 0.109804 0 0 0 0.05 0"
          />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_1434_54215"
            result="effect3_dropShadow_1434_54215"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect3_dropShadow_1434_54215"
            result="shape"
          />
        </filter>
        <filter
          id="filter5_ddd_1434_54215"
          x="358"
          y="882"
          width="377"
          height="75"
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
          <feOffset dy="1" />
          <feGaussianBlur stdDeviation="0.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.180392 0 0 0 0 0.2 0 0 0 0 0.219608 0 0 0 0.1 0"
          />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_1434_54215" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feMorphology
            radius="1"
            operator="dilate"
            in="SourceAlpha"
            result="effect2_dropShadow_1434_54215"
          />
          <feOffset />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix type="matrix" values="0 0 0 0 0.18 0 0 0 0 0.2 0 0 0 0 0.22 0 0 0 0.08 0" />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_1434_54215"
            result="effect2_dropShadow_1434_54215"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="1" />
          <feGaussianBlur stdDeviation="0.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.0862745 0 0 0 0 0.0941176 0 0 0 0 0.109804 0 0 0 0.05 0"
          />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_1434_54215"
            result="effect3_dropShadow_1434_54215"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect3_dropShadow_1434_54215"
            result="shape"
          />
        </filter>
        <radialGradient
          id="paint0_radial_1434_54215"
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
          id="paint1_radial_1434_54215"
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
          id="paint2_radial_1434_54215"
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
          id="paint3_radial_1434_54215"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(339.5 441) rotate(-129.32) scale(535.79 607.057)"
        >
          <stop stop-color="#8366FF" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
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
        id="mask0_1434_54357"
        style="mask-type:alpha"
        maskUnits="userSpaceOnUse"
        x="0"
        y="0"
        width="1184"
        height="1045"
      >
        <rect width="1184" height="1045" fill="url(#paint0_radial_1434_54357)" fill-opacity="0.4" />
        <rect width="1184" height="1045" fill="url(#paint1_radial_1434_54357)" fill-opacity="0.4" />
        <rect width="1184" height="1045" fill="url(#paint2_radial_1434_54357)" fill-opacity="0.4" />
        <rect width="1184" height="1045" fill="url(#paint3_radial_1434_54357)" fill-opacity="0.4" />
      </mask>
      <g mask="url(#mask0_1434_54357)">
        <path
          d="M929 173V287.5H786"
          stroke="#3A3A3A"
          stroke-linejoin="round"
          stroke-dasharray="10 10"
        />
        <path
          d="M268 172V286.5H411"
          stroke="#3A3A3A"
          stroke-linejoin="round"
          stroke-dasharray="10 10"
        />
        <path
          d="M478.5 721.501C478.224 721.501 478 721.725 478 722.001C478 722.277 478.224 722.501 478.5 722.501V721.501ZM710 761.5C710.276 761.5 710.5 761.276 710.5 761C710.5 760.724 710.276 760.5 710 760.5V761.5ZM592.5 835V835.5C592.776 835.5 593 835.276 593 835H592.5ZM559.5 835V834.5C559.224 834.5 559 834.724 559 835H559.5ZM559 882.5C559 882.776 559.224 883 559.5 883C559.776 883 560 882.776 560 882.5H559ZM592 326.013C592 326.289 592.224 326.513 592.5 326.513C592.776 326.513 593 326.289 593 326.013H592ZM593 336.038C593 335.761 592.776 335.538 592.5 335.538C592.224 335.538 592 335.761 592 336.038H593ZM592 346.063C592 346.339 592.224 346.563 592.5 346.563C592.776 346.563 593 346.339 593 346.063H592ZM593 356.088C593 355.811 592.776 355.588 592.5 355.588C592.224 355.588 592 355.811 592 356.088H593ZM592 366.113C592 366.389 592.224 366.613 592.5 366.613C592.776 366.613 593 366.389 593 366.113H592ZM593 376.138C593 375.862 592.776 375.638 592.5 375.638C592.224 375.638 592 375.862 592 376.138H593ZM592 386.163C592 386.439 592.224 386.663 592.5 386.663C592.776 386.663 593 386.439 593 386.163H592ZM593 396.188C593 395.912 592.776 395.688 592.5 395.688C592.224 395.688 592 395.912 592 396.188H593ZM592 406.213C592 406.489 592.224 406.713 592.5 406.713C592.776 406.713 593 406.489 593 406.213H592ZM593 416.238C593 415.962 592.776 415.738 592.5 415.738C592.224 415.738 592 415.962 592 416.238H593ZM592 426.263C592 426.539 592.224 426.763 592.5 426.763C592.776 426.763 593 426.539 593 426.263H592ZM593 436.288C593 436.012 592.776 435.788 592.5 435.788C592.224 435.788 592 436.012 592 436.288H593ZM592 446.313C592 446.589 592.224 446.813 592.5 446.813C592.776 446.813 593 446.589 593 446.313H592ZM593 456.338C593 456.062 592.776 455.838 592.5 455.838C592.224 455.838 592 456.062 592 456.338H593ZM592 466.363C592 466.639 592.224 466.863 592.5 466.863C592.776 466.863 593 466.639 593 466.363H592ZM593 476.388C593 476.112 592.776 475.888 592.5 475.888C592.224 475.888 592 476.112 592 476.388H593ZM592 486.413C592 486.689 592.224 486.913 592.5 486.913C592.776 486.913 593 486.689 593 486.413H592ZM593 496.438C593 496.162 592.776 495.938 592.5 495.938C592.224 495.938 592 496.162 592 496.438H593ZM592 506.463C592 506.739 592.224 506.963 592.5 506.963C592.776 506.963 593 506.739 593 506.463H592ZM593 516.488C593 516.212 592.776 515.988 592.5 515.988C592.224 515.988 592 516.212 592 516.488H593ZM592 526.513C592 526.789 592.224 527.013 592.5 527.013C592.776 527.013 593 526.789 593 526.513H592ZM593 536.538C593 536.262 592.776 536.038 592.5 536.038C592.224 536.038 592 536.262 592 536.538H593ZM592 546.563C592 546.839 592.224 547.063 592.5 547.063C592.776 547.063 593 546.839 593 546.563H592ZM593 556.588C593 556.312 592.776 556.088 592.5 556.088C592.224 556.088 592 556.312 592 556.588H593ZM592 566.613C592 566.889 592.224 567.113 592.5 567.113C592.776 567.113 593 566.889 593 566.613H592ZM593 576.638C593 576.362 592.776 576.138 592.5 576.138C592.224 576.138 592 576.362 592 576.638H593ZM592 586.663C592 586.939 592.224 587.163 592.5 587.163C592.776 587.163 593 586.939 593 586.663H592ZM593 596.688C593 596.412 592.776 596.188 592.5 596.188C592.224 596.188 592 596.412 592 596.688H593ZM592 606.713C592 606.989 592.224 607.213 592.5 607.213C592.776 607.213 593 606.989 593 606.713H592ZM593 616.738C593 616.462 592.776 616.238 592.5 616.238C592.224 616.238 592 616.462 592 616.738H593ZM592 626.763C592 627.039 592.224 627.263 592.5 627.263C592.776 627.263 593 627.039 593 626.763H592ZM593 636.788C593 636.512 592.776 636.288 592.5 636.288C592.224 636.288 592 636.512 592 636.788H593ZM592 646.813C592 647.09 592.224 647.313 592.5 647.313C592.776 647.313 593 647.09 593 646.813H592ZM593 656.838C593 656.562 592.776 656.338 592.5 656.338C592.224 656.338 592 656.562 592 656.838H593ZM592 666.863C592 667.14 592.224 667.363 592.5 667.363C592.776 667.363 593 667.14 593 666.863H592ZM593 676.888C593 676.612 592.776 676.388 592.5 676.388C592.224 676.388 592 676.612 592 676.888H593ZM592 686.913C592 687.19 592.224 687.413 592.5 687.413C592.776 687.413 593 687.19 593 686.913H592ZM593 696.939C593 696.662 592.776 696.439 592.5 696.439C592.224 696.439 592 696.662 592 696.939H593ZM592 706.964C592 707.24 592.224 707.464 592.5 707.464C592.776 707.464 593 707.24 593 706.964H592ZM593 716.989C593 716.712 592.776 716.489 592.5 716.489C592.224 716.489 592 716.712 592 716.989H593ZM483.25 722.501C483.526 722.501 483.75 722.277 483.75 722.001C483.75 721.725 483.526 721.501 483.25 721.501V722.501ZM492.75 721.501C492.474 721.501 492.25 721.725 492.25 722.001C492.25 722.277 492.474 722.501 492.75 722.501V721.501ZM502.25 722.501C502.526 722.501 502.75 722.277 502.75 722.001C502.75 721.725 502.526 721.501 502.25 721.501V722.501ZM511.75 721.501C511.474 721.501 511.25 721.725 511.25 722.001C511.25 722.277 511.474 722.501 511.75 722.501V721.501ZM521.25 722.501C521.526 722.501 521.75 722.277 521.75 722.001C521.75 721.725 521.526 721.501 521.25 721.501V722.501ZM530.75 721.501C530.474 721.501 530.25 721.725 530.25 722.001C530.25 722.277 530.474 722.501 530.75 722.501V721.501ZM540.25 722.501C540.526 722.501 540.75 722.277 540.75 722.001C540.75 721.725 540.526 721.501 540.25 721.501V722.501ZM549.75 721.501C549.474 721.501 549.25 721.725 549.25 722.001C549.25 722.277 549.474 722.501 549.75 722.501V721.501ZM559.25 722.501C559.526 722.501 559.75 722.277 559.75 722.001C559.75 721.725 559.526 721.501 559.25 721.501V722.501ZM568.75 721.501C568.474 721.501 568.25 721.725 568.25 722.001C568.25 722.277 568.474 722.501 568.75 722.501V721.501ZM578.25 722.501C578.526 722.501 578.75 722.277 578.75 722.001C578.75 721.725 578.526 721.501 578.25 721.501V722.501ZM587.75 721.501C587.474 721.501 587.25 721.725 587.25 722.001C587.25 722.277 587.474 722.501 587.75 722.501V721.501ZM592 726.876C592 727.152 592.224 727.376 592.5 727.376C592.776 727.376 593 727.152 593 726.876H592ZM593 736.626C593 736.35 592.776 736.126 592.5 736.126C592.224 736.126 592 736.35 592 736.626H593ZM592 746.375C592 746.652 592.224 746.875 592.5 746.875C592.776 746.875 593 746.652 593 746.375H592ZM593 756.125C593 755.849 592.776 755.625 592.5 755.625C592.224 755.625 592 755.849 592 756.125H593ZM597.396 761.5C597.672 761.5 597.896 761.276 597.896 761C597.896 760.724 597.672 760.5 597.396 760.5V761.5ZM607.188 760.5C606.911 760.5 606.688 760.724 606.688 761C606.688 761.276 606.911 761.5 607.188 761.5V760.5ZM616.979 761.5C617.255 761.5 617.479 761.276 617.479 761C617.479 760.724 617.255 760.5 616.979 760.5V761.5ZM626.771 760.5C626.495 760.5 626.271 760.724 626.271 761C626.271 761.276 626.495 761.5 626.771 761.5V760.5ZM636.562 761.5C636.839 761.5 637.062 761.276 637.062 761C637.062 760.724 636.839 760.5 636.562 760.5V761.5ZM646.354 760.5C646.078 760.5 645.854 760.724 645.854 761C645.854 761.276 646.078 761.5 646.354 761.5V760.5ZM656.146 761.5C656.422 761.5 656.646 761.276 656.646 761C656.646 760.724 656.422 760.5 656.146 760.5V761.5ZM665.938 760.5C665.661 760.5 665.438 760.724 665.438 761C665.438 761.276 665.661 761.5 665.938 761.5V760.5ZM675.729 761.5C676.005 761.5 676.229 761.276 676.229 761C676.229 760.724 676.005 760.5 675.729 760.5V761.5ZM685.521 760.5C685.245 760.5 685.021 760.724 685.021 761C685.021 761.276 685.245 761.5 685.521 761.5V760.5ZM695.312 761.5C695.589 761.5 695.812 761.276 695.812 761C695.812 760.724 695.589 760.5 695.312 760.5V761.5ZM705.104 760.5C704.828 760.5 704.604 760.724 704.604 761C704.604 761.276 704.828 761.5 705.104 761.5V760.5ZM560 876.562C560 876.286 559.776 876.062 559.5 876.062C559.224 876.062 559 876.286 559 876.562H560ZM559 864.688C559 864.964 559.224 865.188 559.5 865.188C559.776 865.188 560 864.964 560 864.688H559ZM560 852.812C560 852.536 559.776 852.312 559.5 852.312C559.224 852.312 559 852.536 559 852.812H560ZM559 840.938C559 841.214 559.224 841.438 559.5 841.438C559.776 841.438 560 841.214 560 840.938H559ZM563.625 835.5C563.901 835.5 564.125 835.276 564.125 835C564.125 834.724 563.901 834.5 563.625 834.5V835.5ZM571.875 834.5C571.599 834.5 571.375 834.724 571.375 835C571.375 835.276 571.599 835.5 571.875 835.5V834.5ZM580.125 835.5C580.401 835.5 580.625 835.276 580.625 835C580.625 834.724 580.401 834.5 580.125 834.5V835.5ZM588.375 834.5C588.099 834.5 587.875 834.724 587.875 835C587.875 835.276 588.099 835.5 588.375 835.5V834.5ZM593 830.375C593 830.099 592.776 829.875 592.5 829.875C592.224 829.875 592 830.099 592 830.375H593ZM592 821.125C592 821.401 592.224 821.625 592.5 821.625C592.776 821.625 593 821.401 593 821.125H592ZM593 811.875C593 811.599 592.776 811.375 592.5 811.375C592.224 811.375 592 811.599 592 811.875H593ZM592 802.625C592 802.901 592.224 803.125 592.5 803.125C592.776 803.125 593 802.901 593 802.625H592ZM593 793.375C593 793.099 592.776 792.875 592.5 792.875C592.224 792.875 592 793.099 592 793.375H593ZM592 784.125C592 784.401 592.224 784.625 592.5 784.625C592.776 784.625 593 784.401 593 784.125H592ZM593 774.875C593 774.599 592.776 774.375 592.5 774.375C592.224 774.375 592 774.599 592 774.875H593ZM592 765.625C592 765.901 592.224 766.125 592.5 766.125C592.776 766.125 593 765.901 593 765.625H592ZM592 321V326.013H593V321H592ZM592 336.038V346.063H593V336.038H592ZM592 356.088V366.113H593V356.088H592ZM592 376.138V386.163H593V376.138H592ZM592 396.188V406.213H593V396.188H592ZM592 416.238V426.263H593V416.238H592ZM592 436.288V446.313H593V436.288H592ZM592 456.338V466.363H593V456.338H592ZM592 476.388V486.413H593V476.388H592ZM592 496.438V506.463H593V496.438H592ZM592 516.488V526.513H593V516.488H592ZM592 536.538V546.563H593V536.538H592ZM592 556.588V566.613H593V556.588H592ZM592 576.638V586.663H593V576.638H592ZM592 596.688V606.713H593V596.688H592ZM592 616.738V626.763H593V616.738H592ZM592 636.788V646.813H593V636.788H592ZM592 656.838V666.863H593V656.838H592ZM592 676.888V686.913H593V676.888H592ZM592 696.939V706.964H593V696.939H592ZM592 716.989V722.001H593V716.989H592ZM478.5 722.501H483.25V721.501H478.5V722.501ZM492.75 722.501H502.25V721.501H492.75V722.501ZM511.75 722.501H521.25V721.501H511.75V722.501ZM530.75 722.501H540.25V721.501H530.75V722.501ZM549.75 722.501H559.25V721.501H549.75V722.501ZM568.75 722.501H578.25V721.501H568.75V722.501ZM587.75 722.501H592.5V721.501H587.75V722.501ZM592 722.001V726.876H593V722.001H592ZM592 736.626V746.375H593V736.626H592ZM592 756.125V761H593V756.125H592ZM592.5 761.5H597.396V760.5H592.5V761.5ZM607.188 761.5H616.979V760.5H607.188V761.5ZM626.771 761.5H636.562V760.5H626.771V761.5ZM646.354 761.5H656.146V760.5H646.354V761.5ZM665.938 761.5H675.729V760.5H665.938V761.5ZM685.521 761.5H695.312V760.5H685.521V761.5ZM705.104 761.5H710V760.5H705.104V761.5ZM560 882.5V876.562H559V882.5H560ZM560 864.688V852.812H559V864.688H560ZM560 840.938V835H559V840.938H560ZM559.5 835.5H563.625V834.5H559.5V835.5ZM571.875 835.5H580.125V834.5H571.875V835.5ZM588.375 835.5H592.5V834.5H588.375V835.5ZM593 835V830.375H592V835H593ZM593 821.125V811.875H592V821.125H593ZM593 802.625V793.375H592V802.625H593ZM593 784.125V774.875H592V784.125H593ZM593 765.625V761H592V765.625H593Z"
          fill="#3A3A3A"
        />
        <g filter="url(#filter0_ddd_1434_54357)">
          <path
            d="M86 112C86 105.373 91.3726 100 98 100H449C455.627 100 461 105.373 461 112V160C461 166.627 455.627 172 449 172H98C91.3726 172 86 166.627 86 160V112Z"
            fill="#0E0E0E"
          />
          <rect x="98" y="112" width="48" height="48" rx="6" fill="#181818" />
          <rect x="162" y="112" width="242" height="20" rx="6" fill="#181818" />
          <rect x="166" y="146" width="12" height="12" rx="6" fill="#181818" />
          <rect x="180" y="146" width="17" height="12" rx="6" fill="#181818" />
          <rect x="214" y="146" width="12" height="12" rx="6" fill="#181818" />
          <rect x="228" y="146" width="39" height="12" rx="6" fill="#181818" />
          <rect x="420" y="124" width="24" height="24" rx="6" fill="#181818" />
        </g>
        <g filter="url(#filter1_ddd_1434_54357)">
          <path
            d="M411 261C411 254.373 416.373 249 423 249H774C780.627 249 786 254.373 786 261V309C786 315.627 780.627 321 774 321H423C416.373 321 411 315.627 411 309V261Z"
            fill="#0E0E0E"
          />
          <rect x="423" y="261" width="48" height="48" rx="6" fill="#181818" />
          <rect x="487" y="261" width="242" height="20" rx="6" fill="#181818" />
          <rect x="491" y="295" width="12" height="12" rx="6" fill="#181818" />
          <rect x="505" y="295" width="17" height="12" rx="6" fill="#181818" />
          <rect x="539" y="295" width="12" height="12" rx="6" fill="#181818" />
          <rect x="553" y="295" width="39" height="12" rx="6" fill="#181818" />
          <rect x="745" y="273" width="24" height="24" rx="6" fill="#181818" />
        </g>
        <g filter="url(#filter2_ddd_1434_54357)">
          <path
            d="M722 102C722 95.3726 727.373 90 734 90H1085C1091.63 90 1097 95.3726 1097 102V150C1097 156.627 1091.63 162 1085 162H734C727.373 162 722 156.627 722 150V102Z"
            fill="#0E0E0E"
          />
          <rect x="734" y="102" width="48" height="48" rx="6" fill="#181818" />
          <rect x="798" y="102" width="242" height="20" rx="6" fill="#181818" />
          <rect x="802" y="136" width="12" height="12" rx="6" fill="#181818" />
          <rect x="816" y="136" width="17" height="12" rx="6" fill="#181818" />
          <rect x="850" y="136" width="12" height="12" rx="6" fill="#181818" />
          <rect x="864" y="136" width="39" height="12" rx="6" fill="#181818" />
          <rect x="1056" y="114" width="24" height="24" rx="6" fill="#181818" />
        </g>
        <g filter="url(#filter3_ddd_1434_54357)">
          <path
            d="M710 738C710 731.373 715.373 726 722 726H1073C1079.63 726 1085 731.373 1085 738V786C1085 792.627 1079.63 798 1073 798H722C715.373 798 710 792.627 710 786V738Z"
            fill="#0E0E0E"
          />
          <rect x="722" y="738" width="48" height="48" rx="6" fill="#181818" />
          <rect x="786" y="738" width="242" height="20" rx="6" fill="#181818" />
          <rect x="790" y="772" width="12" height="12" rx="6" fill="#181818" />
          <rect x="804" y="772" width="17" height="12" rx="6" fill="#181818" />
          <rect x="838" y="772" width="12" height="12" rx="6" fill="#181818" />
          <rect x="852" y="772" width="39" height="12" rx="6" fill="#181818" />
          <rect x="1044" y="750" width="24" height="24" rx="6" fill="#181818" />
        </g>
        <g filter="url(#filter4_ddd_1434_54357)">
          <path
            d="M103 698C103 691.373 108.373 686 115 686H466C472.627 686 478 691.373 478 698V746C478 752.627 472.627 758 466 758H115C108.373 758 103 752.627 103 746V698Z"
            fill="#0E0E0E"
          />
          <rect x="115" y="698" width="48" height="48" rx="6" fill="#181818" />
          <rect x="179" y="698" width="242" height="20" rx="6" fill="#181818" />
          <rect x="183" y="732" width="12" height="12" rx="6" fill="#181818" />
          <rect x="197" y="732" width="17" height="12" rx="6" fill="#181818" />
          <rect x="231" y="732" width="12" height="12" rx="6" fill="#181818" />
          <rect x="245" y="732" width="39" height="12" rx="6" fill="#181818" />
          <rect x="437" y="710" width="24" height="24" rx="6" fill="#181818" />
        </g>
        <g filter="url(#filter5_ddd_1434_54357)">
          <path
            d="M359 895C359 888.373 364.373 883 371 883H722C728.627 883 734 888.373 734 895V943C734 949.627 728.627 955 722 955H371C364.373 955 359 949.627 359 943V895Z"
            fill="#0E0E0E"
          />
          <rect x="371" y="895" width="48" height="48" rx="6" fill="#181818" />
          <rect x="435" y="895" width="242" height="20" rx="6" fill="#181818" />
          <rect x="439" y="929" width="12" height="12" rx="6" fill="#181818" />
          <rect x="453" y="929" width="17" height="12" rx="6" fill="#181818" />
          <rect x="487" y="929" width="12" height="12" rx="6" fill="#181818" />
          <rect x="501" y="929" width="39" height="12" rx="6" fill="#181818" />
          <rect x="693" y="907" width="24" height="24" rx="6" fill="#181818" />
        </g>
      </g>
      <defs>
        <filter
          id="filter0_ddd_1434_54357"
          x="83"
          y="99"
          width="381"
          height="78"
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
          <feOffset dy="2" />
          <feGaussianBlur stdDeviation="1.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.3 0" />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_1434_54357" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feMorphology
            radius="1"
            operator="dilate"
            in="SourceAlpha"
            result="effect2_dropShadow_1434_54357"
          />
          <feOffset />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.443137 0 0 0 0 0.443137 0 0 0 0 0.443137 0 0 0 0.45 0"
          />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_1434_54357"
            result="effect2_dropShadow_1434_54357"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="1" />
          <feGaussianBlur stdDeviation="0.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.054902 0 0 0 0 0.054902 0 0 0 0 0.054902 0 0 0 0.3 0"
          />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_1434_54357"
            result="effect3_dropShadow_1434_54357"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect3_dropShadow_1434_54357"
            result="shape"
          />
        </filter>
        <filter
          id="filter1_ddd_1434_54357"
          x="408"
          y="248"
          width="381"
          height="78"
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
          <feOffset dy="2" />
          <feGaussianBlur stdDeviation="1.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.3 0" />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_1434_54357" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feMorphology
            radius="1"
            operator="dilate"
            in="SourceAlpha"
            result="effect2_dropShadow_1434_54357"
          />
          <feOffset />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.443137 0 0 0 0 0.443137 0 0 0 0 0.443137 0 0 0 0.45 0"
          />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_1434_54357"
            result="effect2_dropShadow_1434_54357"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="1" />
          <feGaussianBlur stdDeviation="0.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.054902 0 0 0 0 0.054902 0 0 0 0 0.054902 0 0 0 0.3 0"
          />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_1434_54357"
            result="effect3_dropShadow_1434_54357"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect3_dropShadow_1434_54357"
            result="shape"
          />
        </filter>
        <filter
          id="filter2_ddd_1434_54357"
          x="719"
          y="89"
          width="381"
          height="78"
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
          <feOffset dy="2" />
          <feGaussianBlur stdDeviation="1.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.3 0" />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_1434_54357" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feMorphology
            radius="1"
            operator="dilate"
            in="SourceAlpha"
            result="effect2_dropShadow_1434_54357"
          />
          <feOffset />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.443137 0 0 0 0 0.443137 0 0 0 0 0.443137 0 0 0 0.45 0"
          />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_1434_54357"
            result="effect2_dropShadow_1434_54357"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="1" />
          <feGaussianBlur stdDeviation="0.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.054902 0 0 0 0 0.054902 0 0 0 0 0.054902 0 0 0 0.3 0"
          />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_1434_54357"
            result="effect3_dropShadow_1434_54357"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect3_dropShadow_1434_54357"
            result="shape"
          />
        </filter>
        <filter
          id="filter3_ddd_1434_54357"
          x="707"
          y="725"
          width="381"
          height="78"
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
          <feOffset dy="2" />
          <feGaussianBlur stdDeviation="1.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.3 0" />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_1434_54357" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feMorphology
            radius="1"
            operator="dilate"
            in="SourceAlpha"
            result="effect2_dropShadow_1434_54357"
          />
          <feOffset />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.443137 0 0 0 0 0.443137 0 0 0 0 0.443137 0 0 0 0.45 0"
          />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_1434_54357"
            result="effect2_dropShadow_1434_54357"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="1" />
          <feGaussianBlur stdDeviation="0.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.054902 0 0 0 0 0.054902 0 0 0 0 0.054902 0 0 0 0.3 0"
          />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_1434_54357"
            result="effect3_dropShadow_1434_54357"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect3_dropShadow_1434_54357"
            result="shape"
          />
        </filter>
        <filter
          id="filter4_ddd_1434_54357"
          x="100"
          y="685"
          width="381"
          height="78"
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
          <feOffset dy="2" />
          <feGaussianBlur stdDeviation="1.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.3 0" />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_1434_54357" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feMorphology
            radius="1"
            operator="dilate"
            in="SourceAlpha"
            result="effect2_dropShadow_1434_54357"
          />
          <feOffset />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.443137 0 0 0 0 0.443137 0 0 0 0 0.443137 0 0 0 0.45 0"
          />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_1434_54357"
            result="effect2_dropShadow_1434_54357"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="1" />
          <feGaussianBlur stdDeviation="0.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.054902 0 0 0 0 0.054902 0 0 0 0 0.054902 0 0 0 0.3 0"
          />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_1434_54357"
            result="effect3_dropShadow_1434_54357"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect3_dropShadow_1434_54357"
            result="shape"
          />
        </filter>
        <filter
          id="filter5_ddd_1434_54357"
          x="356"
          y="882"
          width="381"
          height="78"
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
          <feOffset dy="2" />
          <feGaussianBlur stdDeviation="1.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.3 0" />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_1434_54357" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feMorphology
            radius="1"
            operator="dilate"
            in="SourceAlpha"
            result="effect2_dropShadow_1434_54357"
          />
          <feOffset />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.443137 0 0 0 0 0.443137 0 0 0 0 0.443137 0 0 0 0.45 0"
          />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_1434_54357"
            result="effect2_dropShadow_1434_54357"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="1" />
          <feGaussianBlur stdDeviation="0.5" />
          <feComposite in2="hardAlpha" operator="out" />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0.054902 0 0 0 0 0.054902 0 0 0 0 0.054902 0 0 0 0.3 0"
          />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_1434_54357"
            result="effect3_dropShadow_1434_54357"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect3_dropShadow_1434_54357"
            result="shape"
          />
        </filter>
        <radialGradient
          id="paint0_radial_1434_54357"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(883 292) rotate(-43.8958) scale(458.644 519.65)"
        >
          <stop stop-color="#E51C01" />
          <stop offset="1" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint1_radial_1434_54357"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(411.5 627.5) rotate(134.109) scale(591.213 669.853)"
        >
          <stop stop-color="#FFC300" />
          <stop offset="1" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint2_radial_1434_54357"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(725 628.5) rotate(39.3184) scale(557.109 631.212)"
        >
          <stop stop-color="#F44277" />
          <stop offset="1" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint3_radial_1434_54357"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(339.5 441) rotate(-129.32) scale(535.79 607.057)"
        >
          <stop stop-color="#8366FF" />
          <stop offset="1" stop-opacity="0" />
        </radialGradient>
      </defs>
    </svg>
    """
  end
end
