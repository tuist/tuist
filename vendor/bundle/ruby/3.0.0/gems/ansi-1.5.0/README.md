# ANSI

[HOME](http://rubyworks.github.com/ansi) &middot;
[API](http://rubydoc.info/gems/ansi/frames) &middot;
[MAIL](http://googlegroups.com/group/rubyworks-mailinglist)  &middot;
[ISSUES](http://github.com/rubyworks/ansi/issues) &middot;
[SOURCE](http://github.com/rubyworks/ansi)

[![Build Status](https://secure.travis-ci.org/rubyworks/ansi.png)](http://travis-ci.org/rubyworks/ansi)

<br/>

The ANSI project is a collection of ANSI escape code related libraries
enabling ANSI code based colorization and stylization of output.
It is very nice for beautifying shell output.

This collection is based on a set of scripts spun-off from
Ruby Facets. Included are Code (used to be ANSICode), Logger,
ProgressBar and String. In addition the library includes
Terminal which provides information about the current output
device.


## Features

* ANSI::Code provides ANSI codes as module functions.
* String#ansi makes common usage very easy and elegant.
* ANSI::Mixin provides an alternative mixin (like +colored+ gem).
* Very Good coverage of standard ANSI codes.
* Additional clases for colorized columns, tables, loggers and more.


## Synopsis

There are a number of modules and classes provided by the ANSI
package. To get a good understanding of them it is best to pursue 
the [QED documents](http://github.com/rubyworks/ansi/tree/master/qed/)
or the [API documentation](http://rubyworks.github.com/ansi/api/index.html).

At the heart of all the provided libraries lies the ANSI::Code module
which defines ANSI codes as constants and methods. For example:

    require 'ansi/code'

    ANSI.red + "Hello" + ANSI.blue + "World"
    => "\e[31mHello\e[34mWorld"

Or in block form.

    ANSI.red{ "Hello" } + ANSI.blue{ "World" }
    => "\e[31mHello\e[0m\e[34mWorld\e[0m"

The methods defined by this module are used throughout the rest of
the system.


## Installation

### RubyGems

To install with RubyGems simply open a console and type:

    $ sudo gem install ansi

### Setup.rb (not recommended)

Local installation requires Setup.rb (gem install setup),
then [download](http://github.com/rubyworks/ansi/download) the tarball package and type:

    $ tar -xvzf ansi-1.0.0.tgz
    $ cd ansi-1.0.0
    $ sudo setup.rb all

Windows users use 'ruby setup.rb all'.


## Release Notes

Please see HISTORY.md file.


## License & Copyrights

Copyright (c) 2009 Rubyworks

This program is redistributable under the terms of the *FreeBSD* license.

Some pieces of the code are copyrighted by others.

See LICENSE.txt and NOTICE.md files for details.

