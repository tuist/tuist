# Install xcbuddy

xcbuddy is distributed as a macOS application. A macOS application is a folder/bundle that contains the application binaries and other resources like third party frameworks, or assets. In case of xcbuddy, the application bundle contains:

* A macOS application.
* A command line tool.
* Third party frameworks.

xcbuddy releases on the [GitHub repository](https://github.com/xcbuddy/xcbuddy) contain a zip file with the application bundle. You could manually download it, and move the app into your `/Application` folder, however we recommend you to execute the following command on your terminal to install the tool:

```bash
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/xcbuddy/xcbuddy/master/scripts/install)"
```

It will download and run an installation script that performs all the necessary steps to get xcbuddy working on your local environment.

As part of the installation process, the script will create a symbolic link in `/usr/local/bin/xcbuddy` so that you can access the command line tool from anywhere.

You can check if the tool was installed properly by running `xcbuddy` in your terminal.

## Updating xcbuddy

xcbuddy uses [Sparkle](), a third party tool that auto-updates macOS applications. If you woudl like to update your version of xcbuddy you could do it by:

* Running `xcbuddy update`.
* Clicking `xcbuddy > Check for updates` from the status bar app.

In either way, xcbuddy will check if there's any new update and will guide you throw the update process. Optionall you can run the same installation script. I'll override your local version with the new version.
