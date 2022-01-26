## 1.2.2 - 30-Oct-2020
* Added a Gemfile.
* The ffi dependency is now slightly more restrictive.
* Added rake as a development dependency (which it really always was).
* Switched from rdoc to markdown because github wouldn't render it properly.

## 1.2.1 - 17-Mar-2020
* Properly include a LICENSE file as per the Apache-2.0 license.

## 1.2.0 - 5-Jan-2020
* Changed test suite from test-unit to rspec, which was also added as a
  development dependency.
* Several new fields were added to the returned object on Windows. The fields
  are encryption_level, product_type, suite_mask and system_drive.

## 1.1.1 - 10-Dec-2019
* Renamed various text files to include explicit .rdoc extension so that
  they show up more nicely on github.

## 1.1.0 - 29-Aug-2019
* Changed license to Apache-2.0.
* Updated the doc/uname.txt file.
* Minor test updates.

## 1.0.4 - 4-Nov-2018
* Added metadata to the gemspec.
* Updated the cert, which will expire in about 10 years.

## 1.0.3 - 31-Oct-2016
* Updated the gem cert. It will expire on 31-Oct-2019.
* Minor updates to the Rakefile and gemspec.

## 1.0.2 - 3-Sep-2015
* The gem is now signed.
* Modified gemspec and Rakefile to support signing.

## 1.0.1 - 19-Aug-2015
* Modified Platform::IMPL so that it does not include "32" as part of the
  symbol name. This isn't useful since it's the same on 32 or 64-bit Windows.
* Reorganized code a bit so that the VERSION constant is in a single place.
* For consistency, there is also a Platform::VERSION. This is the same value
  as Uname::VERSION.
* Added a test for Sys::Platform::IMPL on Windows.

## 1.0.0 - 19-Aug-2015
* Added a sys-uname.rb shim so that you can require this library with
  "sys-uname" or "sys/uname".
* Added the architecture method for MS Windows.
* Added a Sys::Platform class that adds several boolean methods to check
  your operating system. It also adds the ARCH, OS, and IMPL constants
  to simulate, and ultimately replace, the old "Platform" gem.
* There is now just a single gem, instead of a separate gem for Windows
  and Unix, so you shouldn't need to worry about platform checking.

## 0.9.2 - 1-May-2013
* Added a workaround for a win32ole thread bug. Thanks go to Tianlong Wu
  for the spot.
* Altered platform handling slightly for Windows in the Rakefile.

## 0.9.1 - 3-Jan-2013
* Made FFI functions private.
* Properly alias uname FFI function.
* Fixed the QuantumLength and QuantumType bug again (see 0.8.4), which I
  somehow accidentally reintroduced.

## 0.9.0 - 8-Dec-2011
* Conversion to FFI.
* Added some additional methods and information for Solaris.
* Minor tweaks for 1.9 to silence warnings.

## 0.8.6 - 2-Sep-2011
* Fixed a failing test for Ruby 1.9.x.
* The gemspec for Windows is now 'universal'.
* Some minor doc updates.

## 0.8.5 - 11-Dec-2010
* Removed some non-ascii characters that somehow made it into the source.
* Some updates to the Rakefile, including a default task.

## 0.8.4 - 29-Jan-2010
* Bug fix for Windows 7, which appears to have removed the QuantumLength and
  QuantumType members of the Win32_OperatingSystem class. Thanks go to Mark
  Seymour for the spot. RubyForge bug # 27645.
* Changed license to Artistic 2.0.
* Refactored the Rakefile and gemspec considerably. The gem building code is
  now all inlined within the Rakefile build task itself.
* Minor doc updates and some code reformatting.

## 0.8.3 - 26-Apr-2008
* Added an explicit "require 'time'" in the Windows version because recent
  versions of Ruby now need it.
* Changed the way I do platform checks in the Rakefile.

## 0.8.2 - 22-Nov-2007
* Fixed an issue where Ruby no longer parsed a certain type of date that
  MS Windows uses. See RubyForge Bug #10646 for more information.

## 0.8.1 - 29-Aug-2007
* Made a minor modification to the build script for Linux. It turns out Linux
  has sysctl, but not the necessary mibs for the Uname.model method. Thanks go
  to Mickey Knox (?) for the spot.
* Removed the install.rb file. The code from that program was integrated
  directly into the Rakefile.

## 0.8.0 - 10-Apr-2007
* The Uname.model method should now work on most BSD platforms, not just OS X,
  since it uses the sysctl() function behind the scenes.
* The 'id' method was changed to 'id_number' on HP-UX to avoid confusion with
  the Object.id method.
* The UnameError class is now Uname::Error.
* Added a Rakefile. There are now tasks for building, testing and installing
  this package.
* Removed some pre-setup code from the test suite that was no longer necessary
  as a result of the Rake test task.

## 0.7.4 - 19-Nov-2006
* Internal layout changes, doc updates and gemspec improvements.
* No code changes.

## 0.7.3 - 30-Jul-2006
* Bug fix for 64 bit platforms.
* Minor modification of the extconf.rb file.

## 0.7.2 - 5-Jul-2006
* Removed '?' from the struct member names on MS Windows since these are no
  longer legal.
* Removed duplicate definition of Uname.version on MS Windows (oops).
* Added a gemspec.
* Added inline rdoc documentation to the source files.

## 0.7.1 - 5-May-2005
* Removed the uname.rd file.  The uname.txt file is rdoc friendly, so you
  can autogenerate html from that file if you wish.
* Removed the version.h file - no longer needed now that the Windows version
  is pure Ruby.
* Renamed test.rb to uname_test.rb
* Minor setup modifications to the test suite.
* This package is now hosted on RubyForge.

## 0.7.0 - 11-Jan-2004
* Scrapped the C version for Windows in favor of a pure Ruby version that uses
  WMI + OLE.  I highly recommend using Ruby 1.8.2 or later on Win32 systems.
  Earlier versions may cause segfaults.
* Added the isa_list, hw_provider, hw_serial_number, srpc_domain and
  dhcp_cache methods for Solaris.
* Added install.rb program for Windows, and modified extconf.rb to only run on
  non-Windows systems.
* The 'examples' directory has been moved to the toplevel directory.
* Removed the INSTALL file.  That information is now included in the README.
* Documentation updates.

## 0.6.1 - 25-Apr-2004
* Simplified extconf.rb script and installation instructions.
* Combined three test scripts into a single test script.
* Warranty information added.

## 0.6.0 - 25-Jun-2003
* Added HP-UX support, including the id() class method (HP-UX only)
* Fixed minor bug in extconf.rb (forgot 'require ftools' at top)
* Added HP-UX specific tests and support
* Made test.rb friendlier for folks without TestUnit installed

## 0.5.0 - 16-Jun-2003
* Added OS X support, including the "model" method.  Thanks to Mike Hall
  for the patch
* Removed VERSION() class method.  Use the constant instead
* Moved rd documentation to its own file (under /doc directory)
* Added a version.h file under 'lib' to store VERSION info for
  all source files
* Modified extconf.rb file to handle OS X support.  In addition, moved
  test.rb into a static file under /test, instead of dynamically
  generating it
* Fixed up test suite.  Added OS X specific tests and support.  Should now
  work with TestUnit 0.1.6 or later
    
## 0.4.1 - 7-Feb-2003
* Fixed C89 issue (again) - thanks go to Daniel Zepeda for the spot
* Fixed bugs in extconf.rb file (rescue clause, ftools)

## 0.4.0 - 6-Feb-2003
* MS Windows support!
* Added a test suite and automatic test.rb creation
* Documentation additions/fixes
* Internal directory layout and filename changes (Changelog -> CHANGES)

## 0.3.3 - 6-Jan-2003
* Made the code C89 compliant for older compilers.  Thanks to Paul Brannan
  for teaching me how to fix this in general.
* Moved README to doc/uname.txt
* Created an INSTALL file
* Added a copyright notice
* Added a VERSION class method
* Changed tarball name to reflect RAA package name
* Minor doc changes

## 0.3.2 - 8-Aug-2002
* Changed the struct name returned by the 'uname()' method from
  "Uname::UnameStruct" to just "UnameStruct".  This was to make it
  compliant with future versions of Ruby.  The extra namespace was
  redundant anyway.
* I include the documentation now, instead of making you install rd2 :)

## 0.3.1 - 22-Jul-2002
* Added the 'uname' class method, which returns a struct that contains all
  of the uname information
* Added a test script.  Do 'ruby test.rb' to run it.
* If rd2 is installed on your system, the documentation is automatically
  generated for you.
* Moved html documentation to 'doc' directory.
* Changed version number style to be consistent with other 'Sys' modules
* Now installs into 'Sys-Uname-x.x.x' directory (instead of just 'Uname')

## 0.03 - 6-June-2002
* rd style documentation now inline
* README.html is now uname.html - created via rdtool
* The 'platform()' and 'architecture()' methods have been added for Solaris
* You can now do an 'include Sys' to shorten your syntax
* The whole 'Sys' class has been removed.  Delete your sys.so file if you
  installed a previous version of Sys-Uname

## 0.02 - 3-June-2002
* Potentially fatal memory problems corrected.
* Should now build with C++ as well
* Thanks to Mike Hall for both the spot and the fix
* Added a Changelog file
* Added a README.html file
* Added a Manifest file

## 0.01 - 31-May-2002
* Initial release (unannounced)
