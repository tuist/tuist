# Native branding assets

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

`generate_app_icons.py` uses the same white mark on Atlas's `#087CAA` azure for
opaque iOS icons, Android density-specific launcher icons and adaptive layers.
Run it with the same dependencies and commit its generated assets. Keep adaptive
foreground artwork inside the 66dp safe zone. Platforms apply their own masks.

Once 0.68.2 compiles `AppIcon` but does not merge the partial icon plist or declare
its generated PNG outputs. Both production iOS targets therefore also declare
catalog PNGs as ordinary resources, and `ios/Info.plist` supplies `CFBundleIcons`
and `CFBundleIcons~ipad`. iPad PNG filenames include `~ipad` so actool cannot
leave undeclared extra icons behind in the signed bundle on cache restoration.
Keep the exact `AppIcon60x60@2x.png` filename available: Tuist's preview uploader
resolves `CFBundleIconFiles` to those PNGs. Do not rely only on an icon in
`Assets.car`. `python3 resources/app_icons_test.py` (Python 3.11+) validates catalog
sizes/opacity, both targets' resource declarations and Android references without
image-tool dependencies.
