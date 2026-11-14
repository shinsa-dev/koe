# dmgbuild settings for Koe.dmg, the layout of shinsa's electron-builder dmg block: release.sh dmg passes
# -D app=<Koe.app> -D background=<png>. The positions match ICON in scripts/dmg.py, which draws around them.
# pylint: disable=undefined-variable
import os.path

app = defines["app"]  # noqa: F821
background = defines["background"]  # noqa: F821

format = "ULFO"
filesystem = "APFS"
files = [(app, "Koe.app")]
hide_extensions = ["Koe.app"]
symlinks = {"Applications": "/Applications"}
icon_locations = {"Koe.app": (180, 196), "Applications": (480, 196)}

window_rect = ((200, 120), (660, 432))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
arrange_by = None
include_icon_view_settings = True
include_list_view_settings = False

assert os.path.isfile(background), background
