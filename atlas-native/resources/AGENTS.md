# Native login assets

`generate_login_assets.py` derives the transparent mark from the Atlas server's
`tuist-logo.svg`, the same Tuist mark used by its web login and dashboard, and
recolors Tuist's existing light/dark launch backgrounds into Atlas's azure palette.
Do not use `logo.svg`, which contains the older compass mark. It writes the iOS
asset catalog and Android drawables. Keep the layout, image composition, and colors
consistent across native clients.

Run `python3 atlas-native/resources/generate_login_assets.py` from the repository
root with Pillow and `rsvg-convert` installed when the source branding changes.
Commit the generated assets. Normal builds must not run the generator or depend
on image tooling. Assets are declared native build inputs, not Rust inputs.
