# Install

First of all you need to install *xpm* in your computer. We made the the process very easy for you. Open a terminal, and execute the following command:

```bash
/usr/bin/ruby -e "$(curl -fsSL https://goo.gl/4cbZoL)"
```

It'll pull the latest version of *xpm*, install it, and add an alias to your shell path. Once the process is completed, you should be able to run `xpm` in your terminal. It'll print the list of commands that are available.


> If you are curious about how the install process works, you can check out this [Ruby script](https://github.com/xcode-project-manager/xpm/blob/master/scripts/install) that gets executed when you run the command above.


### Updating xpm

Since we are continuously adding improvements and new features to *xpm* it's important that you can update the app easily as well. *xpm* comes with an `update` command that you can call at any time. It'll check if there's any update for the tool, and if there is, it'll update verything for you:

```bash
xpm update
```

> The auto-update process is provided by the awesome framework [Sparkle](https://sparkle-project.org/) which is extensively used in many macOS applications.