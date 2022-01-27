# RELEASE HISTORY

## 1.5.0 | 2015-01-16

ANSI 1.5 introduces one change that is not backward compatiable. The 
`:clear_line` code no longer clears to the end of the line. Instead it
clears the entire line. If you have used this in the past you
will need to update your code to use `:clear_eol` or `:clear_right`
instead. In addition this release finally fixes some long time issues
with Windows compatability, and a few other bugs. Yeah!

Changes:

* Alias `:right` and `:left` as `:forward` and `:back` respectively.
* Change `:clear_line` to clear whole line, not just to the end of line.
* Add `:cursor_hide` and `:cursor_show` codes.
* Fix and adjust #rgb method to work as one would expect.
* Fix Windows compatability (old code was alwasy using stty).
* Fix duplicated hash key in chart.rb.


## 1.4.3 | 2012-06-26

This release bring two small changes. The first improves support
for Windows by only rescuing LoadError when 'win32console' fails
to load. The second improves the heuritstics used for determining
the current terminal screen width.

Changes:

* Only rescue LoadError on windows require. (#9) [bug]
* Improvements for getting proper screen width.


## 1.4.2 | 2012-01-29

ANSI chains are a new feature inspired by Kazuyoshi Tlacaelel's Isna project.
It is a fluid notation for the String#ansi method, e.g. `"foo".red.on_white`.
Also, ASNI now supports "smart codes", preventing previously applied codes
from undermining the applicaiton of additional codes --a subtle issue that
most other ANSI libraries overlook. Plus a few other improvements including
that of the API documentation.

Changes:

* Add ANSI::Chains, extending String#ansi method.
* Support smart code application.
* Add Diff#to_a and shortcut to it via Diff.diff().
* Improve #colorize method in ProgressBar.
* Change ProgressBar's default mark to `|` instead of `o`.
* Fix Curses return order of screen cols and rows.
* Support center alignment in Columns.
* Support custom padding for Columns.


## 1.4.1 | 2011-11-09

This release simply fixes a documentation issue, to make sure
QED.rdoc appears in the YARD docs. And a shout-out to Chad Perrin
for submitting some doc fixes for this project and a few other
Rubyworks projects.

Changes:

* Adjust .yardopts file.
* Documentation fixes.


## 1.4.0 | 2011-11-05

New release adds a HexDump class for colorized byte string dumps
and fixes some minor cell size issues with the Table class.
This release also modernizes the build config and changes the
license to BSD-2-Clause.

Changes:

* Add HexDump class.
* Fix cell size of tables when ANSI codes are used.
* Fix extra ansi codes in tables without format.
* Modernize build configuration.
* Switch to BSD-2-Clause license.


## 1.3.0 | 2011-06-30

This release cleans up the Code module. It adds support for x-term
256 color codes. Also, the Diff class is now awesome, making use of
an LCS algorithm. But the most important difference with this release
is that the String core extensions are in their own file, core.rb.
If you want to use them you will need to require `ansi` or `ansi/core`.

Changes:

* Clean-up Code module.
* Utilize common chart for Code methods.
* Constants now have their own module.
* Move core methods to `ansi/core.rb`.
* Add XTerm 256 color code support.
* Improved Diff class with LCS algorithm.


## 1.2.5 | 2011-05-03

This release introduces a preliminary rendition of a Diff class
for getting colorized comparisons of strings and other objects.
It's not officially supported yet, so this is only a point release.

Changes:

* Added Diff class for colorized comparisons.
* Fixed minor issue with Columns format block; col comes before row.


## 1.2.4 | 2011-04-29

This release improves to the ANSI::Columns class. In particular the
layout is more consistent with intended functionality.

Changes:

* Improved ANSI::Columns to give more consistent output.
* ANSI::Columns#to_s can override number of columns.
* ANSI::Columns can take a String or Array list.


## 1.2.3 | 2011-04-08

Minor release to add #clear method to ProgressBar and provide bug
fix to BBCode.ansi_to_bbcode. Big thanks goes to Junegunn Choi 
for this fix.

Changes:

* Add ProgressBar#clear method.
* Fixed ANSI::BBCode.ansi_to_bbcode and ansi_to_html from omitting lines
without any ansi code (Junegunn Choi).

## 1.2.2 | 2010-06-12

This release removes warnings about string arguments for certain
ANSI::Code methods. While the string form is considered deprecated,
for a few methods there is no use for any argument, so the string
form can remain. In addition, String#unansi has been added to
compliment String#ansi. Lastly, this release also adds the #display
method to ANSI::Mixin.

Changes:

* Remove string argument warnings.
* Add String#unansi and String#unansi!
* Add ANSI::Mixin#display.


## 1.2.1 | 2010-05-10

This release was simply a quick fix to remove the incorrect embedded
version number, until it gets fixed.


## 1.2.0 | 2010-05-10

This release entails numerous improvements. First and foremost
the Code module is transitioning to a block interface only
and phasing out the string argument interface. Admittedly this
is mildly unconventional, but it allows the arguments to be used
as options with common defaults more elegantly.

Another important change is that ANSI::Code no longer provides
String extension methods when included. For this use the new
ANSI::Mixin.

Other improvements include a String extension, #ansi, added to
code.rb, which makes it even easier to apply ANSI codes to strings.
Also, the ANSI::String class has been fixed (a few bugs crept
it with the last release) and continues to improve. On top of all
this testing has substantially improved thanks to QED.

Changes:

* Support string argument for now but with warning
* Bug fixes for ANSI::String
* Add mixin.rb for alternate mixin.
* Many new tests and QED documents.


## 1.1.0 | 2009-10-04

This release is the first toward making the ANSI library
more widely usable.

Changes:

* Add bbcode.rb for conversion between BBCode/ANSI/HTML.
* ProgressBar and Progressbar are the same.
* Other minor underthehood improvements.


## 1.0.1 | 2009-08-15

The release fixes a single bug that should allow Ruby 1.9
to use the ANSI library.

Changes:

* Renamed PLATFORM to RUBY_PLATFORM


## 1.0.0 | 2009-08-15

This is the initial stand-alone release of ANSI, a collection
of ANSI based classes spun-off from Ruby Facets.

Changes:

* Happy Birthday!

