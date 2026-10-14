# Native login assets

`generate_login_assets.py` derives the transparent Atlas mark from the Atlas
server's `logo.svg` and recolors Tuist's existing light/dark launch backgrounds
into Atlas's azure palette. It writes the iOS asset catalog and Android drawables.
Keep the layout, image composition, and colors consistent across native clients.

Run `python3 atlas-native/resources/generate_login_assets.py` from the repository
root with Pillow and `rsvg-convert` installed when the source branding changes.
Commit the generated assets. Normal builds must not run the generator or depend
on image tooling. Assets are declared native build inputs, not Rust inputs.
