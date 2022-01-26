Release Process
===============

* Upgrade gems with `scripts/update-gemspec`
* Bump the version number in `lib/cucumber/wire/version`
* Update `CHANGELOG.md` with the upcoming version number and create a new `In Git` section
* Remove empty sections from `CHANGELOG.md`
* Now release it:

```
git commit -am "Release X.Y.Z"
make release
```
