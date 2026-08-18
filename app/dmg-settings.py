"""dmgbuild settings for the Tuist macOS app disk image.

Replaces create-dmg, which styled the window by telling Finder where to put
the icons over AppleScript. The runner fleet's VMs have no Finder that
answers, so every send waited out the 120 second AppleEvent timeout and the
release could not produce a DMG at all. dmgbuild writes the same layout
straight into the image's .DS_Store, so the styling survives without a GUI
session.

The values below mirror the create-dmg invocation this replaces, including
the defaults it did not spell out: a 10x60 window origin, 16pt labels, and
an unarranged icon view with no toolbar or status bar.
"""

import os

app_path = defines["app"]  # noqa: F821 - injected by dmgbuild
app_name = os.path.basename(app_path)

files = [app_path]
symlinks = {"Applications": "/Applications"}
hide_extensions = [app_name]

icon_locations = {
    app_name: (139, 161),
    "Applications": (467, 161),
}

background = defines["background"]  # noqa: F821 - injected by dmgbuild
format = "UDZO"

default_view = "icon-view"
arrange_by = None
icon_size = 95
text_size = 16
label_pos = "bottom"
window_rect = ((10, 60), (605, 363))

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

include_icon_view_settings = True
include_list_view_settings = False
