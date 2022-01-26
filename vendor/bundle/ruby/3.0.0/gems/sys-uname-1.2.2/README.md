## Description
A cross-platform Ruby interface for getting operating system information. The name
comes from the Unix 'uname' command, but this library works on MS Windows as well.

## Prerequisites
ffi 1.0 or later

## Installation
`gem install sys-uname`

## Synopsis
```
require 'sys/uname' # require 'sys-uname' works, too

# You now have Sys::Uname and Sys::Platform classes available.
 
# Get full information about your system
p Sys::Uname.uname

# Check individual platform details about your system
p Sys::Platform.linux? # => true
p Sys::Platform::ARCH  # => :x86_64
```
   
## Solaris Notes
Users on SunOS get several extra methods: architecture, platform,
hw_serial, hw_provider, srpc_domain, isa_list, and dhcp_cache.

## BSD flavors, including OS X
Users on BSD platforms get the extra Uname.model method.

## HP-UX Notes
HP-UX users get the extra Uname.id_number method. This is actually a
String, not a Fixnum, because that's how it's defined in the utsname
struct.

## MS Windows Notes
The C version for Windows has been completely scrapped in favor of an OLE
plus WMI approach. It is pure Ruby. Please see the MSDN documentation for
the Win32_OperatingSystem class for a complete list of what each of the
UnameStruct members mean.

## The Platform Class
This was added both as a nicer way to check simple information about your
system, and as a replacement for the old 'Platform' gem which is no longer
maintained.

## Future Plans
I may dump the "Uname" portion of this library, and rename the project
to just sys-platform.

## Documentation
For more details, see the 'uname.rdoc' file under the 'doc' directory. 
