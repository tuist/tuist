require 'socket'
require 'time'

# See Ruby bugs #2618 and #7681. This is a workaround.
BEGIN{
  require 'win32ole'
  if RUBY_VERSION.to_f < 2.0
    WIN32OLE.ole_initialize
    at_exit { WIN32OLE.ole_uninitialize }
  end
}

# The Sys module provides a namespace only.
module Sys

  # The Uname class encapsulates uname (platform) information.
  class Uname

    # This is the error raised if any of the Sys::Uname methods should fail.
    class Error < StandardError; end

    fields = %w[
      boot_device
      build_number
      build_type
      caption
      code_set
      country_code
      creation_class_name
      cscreation_class_name
      csd_version
      cs_name
      current_time_zone
      debug
      description
      distributed
      encryption_level
      foreground_application_boost
      free_physical_memory
      free_space_in_paging_files
      free_virtual_memory
      install_date
      last_bootup_time
      local_date_time
      locale
      manufacturer
      max_number_of_processes
      max_process_memory_size
      name
      number_of_licensed_users
      number_of_processes
      number_of_users
      organization
      os_language
      os_product_suite
      os_type
      other_type_description
      plus_product_id
      plus_version_number
      primary
      product_type
      quantum_length
      quantum_type
      registered_user
      serial_number
      service_pack_major_version
      service_pack_minor_version
      size_stored_in_paging_files
      status
      suite_mask
      system_device
      system_directory
      system_drive
      total_swap_space_size
      total_virtual_memory_size
      total_visible_memory_size
      version
      windows_directory
    ]

    # The UnameStruct is used to store platform information for some methods.
    UnameStruct = Struct.new("UnameStruct", *fields)

    # Returns the version plus patch information of the operating system,
    # separated by a hyphen, e.g. "2915-Service Pack 2".
    #--
    # The instance name is unpredictable, so we have to resort to using
    # the 'InstancesOf' method to get the data we need, rather than
    # including it as part of the connection.
    #
    def self.version(host=Socket.gethostname)
      cs = "winmgmts://#{host}/root/cimv2"
      begin
        wmi = WIN32OLE.connect(cs)
      rescue WIN32OLERuntimeError => e
        raise Error, e
      else
        wmi.InstancesOf("Win32_OperatingSystem").each{ |ole|
          str = "#{ole.Version} #{ole.BuildNumber}-"
          str << "#{ole.ServicePackMajorVersion}"
          return str
        }
      end
    end

    # Returns the operating system name, e.g. "Microsoft Windows XP Home"
    #
    def self.sysname(host=Socket.gethostname)
      cs = "winmgmts:{impersonationLevel=impersonate,(security)}"
      cs << "//#{host}/root/cimv2"
      begin
        wmi = WIN32OLE.connect(cs)
      rescue WIN32OLERuntimeError => e
        raise Error, e
      else
        wmi.InstancesOf("Win32_OperatingSystem").each{ |ole|
          return ole.Caption
        }
      end
    end

    # Returns the nodename.  This is usually, but not necessarily, the
    # same as the system's hostname.
    #
    def self.nodename(host=Socket.gethostname)
      cs = "winmgmts:{impersonationLevel=impersonate,(security)}"
      cs << "//#{host}/root/cimv2"
      begin
        wmi = WIN32OLE.connect(cs)
      rescue WIN32OLERuntimeError => e
        raise Error, e
      else
        wmi.InstancesOf("Win32_OperatingSystem").each{ |ole|
          return ole.CSName
        }
      end
    end

    # Returns the CPU architecture, e.g. "x86"
    #
    def self.architecture(cpu_num=0, host=Socket.gethostname)
      cs = "winmgmts:{impersonationLevel=impersonate,(security)}"
      cs << "//#{host}/root/cimv2:Win32_Processor='cpu#{cpu_num}'"
      begin
        wmi = WIN32OLE.connect(cs)
      rescue WIN32OLERuntimeError => e
        raise Error, e
      else
        case wmi.Architecture
          when 0
            "x86"
          when 1
            "mips"
          when 2
            "alpha"
          when 3
            "powerpc"
          when 6
            "ia64"
          when 9
            "x86_64"
          else
            "unknown"
        end
      end
    end

    # Returns the machine hardware type.  e.g. "i686".
    #--
    # This may or may not return the expected value because some CPU types
    # were unknown to the OS when the OS was originally released.  It
    # appears that MS doesn't necessarily patch this, either.
    #
    def self.machine(cpu_num=0, host=Socket.gethostname)
      cs = "winmgmts:{impersonationLevel=impersonate,(security)}"
      cs << "//#{host}/root/cimv2:Win32_Processor='cpu#{cpu_num}'"
      begin
        wmi = WIN32OLE.connect(cs)
      rescue WIN32OLERuntimeError => e
        raise Error, e
      else
        # Convert a family number into the equivalent string
        case wmi.Family
          when 1
            return "Other"
          when 2
            return "Unknown"
          when 3
            return "8086"
          when 4
            return "80286"
          when 5
            return "80386"
          when 6
            return "80486"
          when 7
            return "8087"
          when 8
            return "80287"
          when 9
            return "80387"
          when 10
            return "80487"
          when 11
            return "Pentium brand"
          when 12
            return "Pentium Pro"
          when 13
            return "Pentium II"
          when 14
            return "Pentium processor with MMX technology"
          when 15
            return "Celeron"
          when 16
            return "Pentium II Xeon"
          when 17
            return "Pentium III"
          when 18
            return "M1 Family"
          when 19
            return "M2 Family"
          when 24
            return "K5 Family"
          when 25
            return "K6 Family"
          when 26
            return "K6-2"
          when 27
            return "K6-3"
          when 28
            return "AMD Athlon Processor Family"
          when 29
            return "AMD Duron Processor"
          when 30
            return "AMD2900 Family"
          when 31
            return "K6-2+"
          when 32
            return "Power PC Family"
          when 33
            return "Power PC 601"
          when 34
            return "Power PC 603"
          when 35
            return "Power PC 603+"
          when 36
            return "Power PC 604"
          when 37
            return "Power PC 620"
          when 38
            return "Power PC X704"
          when 39
            return "Power PC 750"
          when 48
            return "Alpha Family"
          when 49
            return "Alpha 21064"
          when 50
            return "Alpha 21066"
          when 51
            return "Alpha 21164"
          when 52
            return "Alpha 21164PC"
          when 53
            return "Alpha 21164a"
          when 54
            return "Alpha 21264"
          when 55
            return "Alpha 21364"
          when 64
            return "MIPS Family"
          when 65
            return "MIPS R4000"
          when 66
            return "MIPS R4200"
          when 67
            return "MIPS R4400"
          when 68
            return "MIPS R4600"
          when 69
            return "MIPS R10000"
          when 80
            return "SPARC Family"
          when 81
            return "SuperSPARC"
          when 82
            return "microSPARC II"
          when 83
            return "microSPARC IIep"
          when 84
            return "UltraSPARC"
          when 85
            return "UltraSPARC II"
          when 86
            return "UltraSPARC IIi"
          when 87
            return "UltraSPARC III"
          when 88
            return "UltraSPARC IIIi"
          when 96
            return "68040"
          when 97
            return "68xxx Family"
          when 98
            return "68000"
          when 99
            return "68010"
          when 100
            return "68020"
          when 101
            return "68030"
          when 112
            return "Hobbit Family"
          when 120
            return "Crusoe TM5000 Family"
          when 121
            return "Crusoe TM3000 Family"
          when 122
            return "Efficeon TM8000 Family"
          when 128
            return "Weitek"
          when 130
            return "Itanium Processor"
          when 131
            return "AMD Athlon 64 Processor Family"
          when 132
            return "AMD Opteron Processor Family"
          when 144
            return "PA-RISC Family"
          when 145
            return "PA-RISC 8500"
          when 146
            return "PA-RISC 8000"
          when 147
            return "PA-RISC 7300LC"
          when 148
            return "PA-RISC 7200"
          when 149
            return "PA-RISC 7100LC"
          when 150
            return "PA-RISC 7100"
          when 160
            return "V30 Family"
          when 176
            return "Pentium III Xeon"
          when 177
            return "Pentium III Processor with Intel SpeedStep Technology"
          when 178
            return "Pentium 4"
          when 179
            return "Intel Xeon"
          when 180
            return "AS400 Family"
          when 181
            return "Intel Xeon processor MP"
          when 182
            return "AMD AthlonXP Family"
          when 183
            return "AMD AthlonMP Family"
          when 184
            return "Intel Itanium 2"
          when 185
            return "AMD Opteron Family"
          when 190
            return "K7"
          when 198
            return "Intel Core i7-2760QM"
          when 200
            return "IBM390 Family"
          when 201
            return "G4"
          when 202
            return "G5"
          when 203
            return "G6"
          when 204
            return "z/Architecture Base"
          when 250
            return "i860"
          when 251
            return "i960"
          when 260
             return "SH-3"
          when 261
            return "SH-4"
          when 280
            return "ARM"
          when 281
            return "StrongARM"
          when 300
            return "6x86"
          when 301
            return "MediaGX"
          when 302
            return "MII"
          when 320
            return "WinChip"
          when 350
            return "DSP"
          when 500
            return "Video Processor"
          else
            return "Unknown"
        end
      end
    end

    # Returns the release number, e.g. 5.1.2600.
    #
    def self.release(host=Socket.gethostname)
      cs = "winmgmts://#{host}/root/cimv2"
      begin
        wmi = WIN32OLE.connect(cs)
      rescue WIN32OLERuntimeError => e
        raise Error, e
      else
        wmi.InstancesOf("Win32_OperatingSystem").each{ |ole|
          return ole.Version
        }
      end
    end

    # Returns a struct of type UnameStruct that contains sysname, nodename,
    # machine, version, and release, as well as a plethora of other fields.
    # Please see the MSDN documentation for what each of these fields mean.
    #
    def self.uname(host=Socket.gethostname)
      cs = "winmgmts://#{host}/root/cimv2"
      begin
        wmi = WIN32OLE.connect(cs)
      rescue WIN32OLERuntimeError => e
        raise Error, e
      else
        wmi.InstancesOf("Win32_OperatingSystem").each{ |os|
          return UnameStruct.new(
            os.BootDevice,
            os.BuildNumber,
            os.BuildType,
            os.Caption,
            os.CodeSet,
            os.CountryCode,
            os.CreationClassName,
            os.CSCreationClassName,
            os.CSDVersion,
            os.CSName,
            os.CurrentTimeZone,
            os.Debug,
            os.Description,
            os.Distributed,
            os.EncryptionLevel,
            os.ForegroundApplicationBoost,
            self.convert(os.FreePhysicalMemory),
            self.convert(os.FreeSpaceInPagingFiles),
            self.convert(os.FreeVirtualMemory),
            self.parse_ms_date(os.InstallDate),
            self.parse_ms_date(os.LastBootUpTime),
            self.parse_ms_date(os.LocalDateTime),
            os.Locale,
            os.Manufacturer,
            os.MaxNumberOfProcesses,
            self.convert(os.MaxProcessMemorySize),
            os.Name,
            os.NumberOfLicensedUsers,
            os.NumberOfProcesses,
            os.NumberOfUsers,
            os.Organization,
            os.OSLanguage,
            os.OSProductSuite,
            os.OSType,
            os.OtherTypeDescription,
            os.PlusProductID,
            os.PlusVersionNumber,
            os.Primary,
            os.ProductType,
            os.respond_to?(:QuantumLength) ? os.QuantumLength : nil,
            os.respond_to?(:QuantumType) ? os.QuantumType : nil,
            os.RegisteredUser,
            os.SerialNumber,
            os.ServicePackMajorVersion,
            os.ServicePackMinorVersion,
            self.convert(os.SizeStoredInPagingFiles),
            os.Status,
            os.SuiteMask,
            os.SystemDevice,
            os.SystemDirectory,
            os.SystemDrive,
            self.convert(os.TotalSwapSpaceSize),
            self.convert(os.TotalVirtualMemorySize),
            self.convert(os.TotalVisibleMemorySize),
            os.Version,
            os.WindowsDirectory
          )
        }
      end
    end

    private

    # Converts a string in the format '20040703074625.015625-360' into a
    # Ruby Time object.
    #
    def self.parse_ms_date(str)
      return if str.nil?
      return Time.parse(str.split('.')[0])
    end

    # There is a bug in win32ole where uint64 types are returned as a
    # String rather than a Fixnum/Bignum.  This deals with that for now.
    #
    def self.convert(str)
      return nil if str.nil?  # Don't turn nil into 0
      return str.to_i
    end
  end
end
