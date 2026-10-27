defmodule TuistWeb.Components.EmptyTabStateBackground do
  @moduledoc """
  SVG component that provides a dot pattern background for empty state UI elements within tabs.
  """
  use Phoenix.Component

  def empty_tab_state_background(assigns) do
    unique_id = UUIDv7.generate()
    mask_id = "mask0_#{unique_id}"
    radial_gradient_id = "paint0_radial_#{unique_id}"

    assigns = assign(assigns, :mask_id, mask_id)
    assigns = assign(assigns, :radial_gradient_id, radial_gradient_id)

    ~H"""
    <svg
      width="1168"
      height="286"
      viewBox="0 0 1168 286"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <mask
        id={@mask_id}
        style="mask-type:alpha"
        maskUnits="userSpaceOnUse"
        x="0"
        y="0"
        width="1168"
        height="286"
      >
        <rect width="1168" height="286" fill={"url(##{@radial_gradient_id})"} />
      </mask>
      <g mask={"url(##{@mask_id})"}>
        <g opacity="0.08">
          <circle cx="24" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="80" cy="87" r="4" fill="#171A1C" />
          <circle cx="136" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="192" cy="87" r="4" fill="#848F9A" />
          <circle cx="248" cy="87" r="4" fill="#171A1C" />
          <circle cx="304" cy="87" r="4" fill="#848F9A" />
          <circle cx="360" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="416" cy="87" r="4" fill="#848F9A" />
          <circle cx="472" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="528" cy="87" r="4" fill="#848F9A" />
          <circle cx="584" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="640" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="696" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="752" cy="87" r="4" fill="#9DA6AF" />
          <circle cx="808" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="864" cy="87" r="4" fill="#848F9A" />
          <circle cx="920" cy="87" r="4" fill="#848F9A" />
          <circle cx="976" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="1032" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="1088" cy="87" r="4" fill="#9DA6AF" />
          <circle cx="1144" cy="87" r="4" fill="#C7CCD1" />
          <circle cx="24" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="80" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="136" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="192" cy="143" r="4" fill="#9DA6AF" />
          <circle cx="248" cy="143" r="4" fill="#9DA6AF" />
          <circle cx="304" cy="143" r="4" fill="#9DA6AF" />
          <circle cx="360" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="416" cy="143" r="4" fill="#9DA6AF" />
          <circle cx="472" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="528" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="584" cy="143" r="4" fill="#848F9A" />
          <circle cx="640" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="696" cy="143" r="4" fill="#9DA6AF" />
          <circle cx="752" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="808" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="864" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="920" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="976" cy="143" r="4" fill="#9DA6AF" />
          <circle cx="1032" cy="143" r="4" fill="#848F9A" />
          <circle cx="1088" cy="143" r="4" fill="#C7CCD1" />
          <circle cx="1144" cy="143" r="4" fill="#9DA6AF" />
          <circle cx="276" cy="199" r="4" fill="#9DA6AF" />
          <circle cx="332" cy="199" r="4" fill="#9DA6AF" />
          <circle cx="388" cy="199" r="4" fill="#C7CCD1" />
          <circle cx="444" cy="199" r="4" fill="#848F9A" />
          <circle cx="500" cy="199" r="4" fill="#C7CCD1" />
          <circle cx="556" cy="199" r="4" fill="#848F9A" />
          <circle cx="612" cy="199" r="4" fill="#9DA6AF" />
          <circle cx="668" cy="199" r="4" fill="#C7CCD1" />
          <circle cx="724" cy="199" r="4" fill="#C7CCD1" />
          <circle cx="780" cy="199" r="4" fill="#C7CCD1" />
          <circle cx="836" cy="199" r="4" fill="#848F9A" />
          <circle cx="892" cy="199" r="4" fill="#171A1C" />
        </g>
      </g>
      <defs>
        <radialGradient
          id={@radial_gradient_id}
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(584 143) rotate(90) scale(396.632 1101.03)"
        >
          <stop />
          <stop offset="1" stop-opacity="0" />
        </radialGradient>
      </defs>
    </svg>
    """
  end
end
