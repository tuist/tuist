# 1.6.8

* Add `upgrade` command
* Add `status_bar_clear` command (requires Xcode 11.4 or newer)
* Add `status_bar_override` command (requires Xcode 11.4 or newer)
* Add `privacy` command (requires Xcode 11.4 or newer)
* Add `push` command (requires Xcode 11.4 or newer)

# 1.6.7

* Turn off sliding hint on keyboard

# 1.6.6

* Fix `device.reset`

# 1.6.4

* Device locale can now be set via `device.set_locale('en_EN')`

# 1.6.3

* Execute `xcode-select` lazily, not during load

# 1.6.2

* Support Xcode 9

# 1.6.1

* Add `SimCtl.warmup`

# 1.6.0

* Breaking change: All `!` have been removed from method names
* Support spawning processes
* Add `device.ready?` method

# 1.5.8

* Support taking screenshots
* Breaking change: Remove `device.disable_keyboard_helpers!`
  Use `device.settings.disable_keyboard_helpers!` instead

# 1.5.7

* Fix SimCtl::Runtime.latest

# 1.5.6

* Fix custom device set path with spaces

# 1.5.5

* Support updating the hardware keyboard setting

# 1.5.4

* Support uninstall command

# 1.5.3

* Support openurl command

# 1.5.2

* Support custom device set path

# 1.5.1

* Let `SimCtl#create_device` wait for the device to be created

# 1.5.0

* `SimCtl#devicetype` throws exception if device type could not be found
* `SimCtl#runtime` throws exception if runtime could not be found
* Support installing and launching an app
