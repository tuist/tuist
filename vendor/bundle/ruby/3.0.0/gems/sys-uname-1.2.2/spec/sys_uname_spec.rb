##############################################################################
# sys_uname_spec.rb
#
# Test suite for the sys-uname library. Run 'rake test' to execute tests.
##############################################################################
require 'rspec'
require 'sys/uname'
require 'rbconfig'

RSpec.describe Sys::Uname do
  context "universal singleton methods" do
    example "version constant is set to expected value" do
      expect(Sys::Uname::VERSION).to eql('1.2.2')
      expect(Sys::Uname::VERSION).to be_frozen
    end

    example "machine singleton method works as expected" do
      expect(described_class).to respond_to(:machine)
      expect{ described_class.machine }.not_to raise_error
      expect(described_class.machine).to be_kind_of(String)
      expect(described_class.machine.size).to be > 0
    end

    example "version singleton method works as expected" do
      expect(described_class).to respond_to(:version)
      expect{ described_class.version }.not_to raise_error
      expect(described_class.version).to be_kind_of(String)
      expect(described_class.version.size).to be > 0
    end

    example "nodename singleton method works as expected" do
      expect(described_class).to respond_to(:nodename)
      expect{ described_class.nodename }.not_to raise_error
      expect(described_class.nodename).to be_kind_of(String)
      expect(described_class.nodename.size).to be > 0
    end

    example "release singleton method works as expected" do
      expect(described_class).to respond_to(:release)
      expect{ described_class.release }.not_to raise_error
      expect(described_class.release).to be_kind_of(String)
      expect(described_class.release.size).to be > 0
    end

    example "sysname singleton method works as expected" do
      expect(described_class).to respond_to(:sysname)
      expect{ described_class.sysname }.not_to raise_error
      expect(described_class.sysname).to be_kind_of(String)
      expect(described_class.sysname.size).to be > 0
    end
  end

  context "singleton methods for Solaris only", :if => RbConfig::CONFIG['host_os'] =~ /sunos|solaris/i do
    example "architecture singleton method works as expected on solaris" do
      expect(described_class).to respond_to(:architecture)
      expect{ described_class.architecture }.not_to raise_error
      expect(described_class.architecture).to be_kind_of(String)
    end

    example "platform singleton method works as expected on solaris" do
      expect(described_class).to respond_to(:platform)
      expect{ described_class.platform }.not_to raise_error
      expect(described_class.platform).to be_kind_of(String)
    end

    example "isa_list singleton method works as expected on solaris" do
      expect(described_class).to respond_to(:isa_list)
      expect{ described_class.isa_list }.not_to raise_error
      expect(described_class.isa_list).to be_kind_of(String)
    end

    example "hw_provider singleton method works as expected on solaris" do
      expect(described_class).to respond_to(:hw_provider)
      expect{ described_class.hw_provider }.not_to raise_error
      expect(described_class.hw_provider).to be_kind_of(String)
    end

    example "hw_serial singleton method works as expected on solaris" do
      expect(described_class).to respond_to(:hw_serial)
      expect{ described_class.hw_serial }.not_to raise_error
      expect(described_class.hw_serial).to be_kind_of(Integer)
    end

    example "srpc_domain singleton method works as expected on solaris" do
      expect(described_class).to respond_to(:srpc_domain)
      expect{ described_class.srpc_domain }.not_to raise_error
      expect(described_class.srpc_domain).to be_kind_of(String)
    end

    example "dhcp_cache singleton method works as expected on solaris" do
      expect(described_class).to respond_to(:dhcp_cache)
      expect{ described_class.dhcp_cache }.not_to raise_error
      expect(described_class.dhcp_cache).to be_kind_of(String)
    end
  end

  context "singleton methods for BSD and Darwin only", :if => RbConfig::CONFIG['host_os'] =~ /darwin|bsd/i do
    example "model singleton method works as expected on BSD and Darwin" do
      expect(described_class).to respond_to(:model)
      expect{ described_class.model }.not_to raise_error
      expect(described_class.model).to be_kind_of(String)
    end
  end

  context "singleton methods for HP-UX only", :if => RbConfig::CONFIG['host_os'] =~ /hpux/i do
    example "id_number singleton method works as expected on HP-UX" do
      expect(described_class).to respond_to(:id_number)
      expect{ described_class.id_number }.not_to raise_error
      expect(described_class.id_number).to be_kind_of(String)
    end
  end

  context "uname struct" do
    example "uname struct contains expected members based on platform" do
      members = %w/sysname nodename machine version release/
      case RbConfig::CONFIG['host_os']
        when /linux/i
          members.push('domainname')
        when /sunos|solaris/i
          members.push(
            'architecture', 'platform', 'hw_serial', 'hw_provider',
            'srpc_domain', 'isa_list', 'dhcp_cache'
          )
        when /powerpc|darwin|bsd/i
          members.push('model')
        when /hpux/i
          members.push('id')
        when /win32|mingw|cygwin|dos|windows/i
          members = %w[
            boot_device build_number build_type caption code_set country_code
            creation_class_name cscreation_class_name csd_version cs_name
            current_time_zone debug description distributed encryption_level
            foreground_application_boost free_physical_memory
            free_space_in_paging_files free_virtual_memory
            install_date last_bootup_time local_date_time locale
            manufacturer max_number_of_processes max_process_memory_size
            name number_of_licensed_users number_of_processes
            number_of_users organization os_language os_product_suite
            os_type other_type_description plus_product_id
            plus_version_number primary product_type quantum_length quantum_type
            registered_user serial_number service_pack_major_version
            service_pack_minor_version size_stored_in_paging_files
            status suite_mask system_device system_directory system_drive total_swap_space_size
            total_virtual_memory_size total_visible_memory_size version
            windows_directory
          ]
      end

      members.map!{ |e| e.to_sym } if RUBY_VERSION.to_f >= 1.9

      expect{ described_class.uname }.not_to raise_error
      expect(described_class.uname).to be_kind_of(Struct)
      expect(described_class.uname.members.sort).to eql(members.sort)
    end
  end

  context "ffi" do
    example "ffi and internal functions are not public" do
      methods = described_class.methods(false).map{ |e| e.to_s }
      expect(methods).not_to include('get_model')
      expect(methods).not_to include('get_si')
      expect(methods).not_to include('uname_c')
      expect(methods).not_to include('sysctl')
      expect(methods).not_to include('sysinfo')
    end
  end

  context "instance methods for MS Windows", :if => File::ALT_SEPARATOR do
    example "boot_device" do
      expect{ described_class.uname.boot_device }.not_to raise_error
      expect(described_class.uname.boot_device).to be_kind_of(String)
    end

    example "build_number" do
      expect{ described_class.uname.build_number }.not_to raise_error
      expect(described_class.uname.build_number).to be_kind_of(String)
    end

    example "build_type" do
      expect{ described_class.uname.build_type }.not_to raise_error
      expect(described_class.uname.build_type).to be_kind_of(String)
    end

    example "caption" do
      expect{ described_class.uname.caption }.not_to raise_error
      expect(described_class.uname.caption).to be_kind_of(String)
    end

    example "code_set" do
      expect{ described_class.uname.code_set }.not_to raise_error
      expect(described_class.uname.code_set).to be_kind_of(String)
    end

    example "country_code" do
      expect{ described_class.uname.country_code }.not_to raise_error
      expect(described_class.uname.country_code).to be_kind_of(String)
    end

    example "creation_class_name" do
      expect{ described_class.uname.creation_class_name }.not_to raise_error
      expect(described_class.uname.creation_class_name).to be_kind_of(String)
    end

    example "cscreation_class_name" do
      expect{ described_class.uname.cscreation_class_name }.not_to raise_error
      expect(described_class.uname.cscreation_class_name).to be_kind_of(String)
    end

    example "csd_version" do
      expect{ described_class.uname.csd_version }.not_to raise_error
      expect(described_class.uname.csd_version).to be_kind_of(String).or be_nil
    end

    example "cs_name" do
      expect{ described_class.uname.cs_name }.not_to raise_error
      expect(described_class.uname.cs_name).to be_kind_of(String)
    end

    example "current_time_zone" do
      expect{ described_class.uname.current_time_zone }.not_to raise_error
      expect(described_class.uname.current_time_zone).to be_kind_of(Integer)
    end

    example "debug" do
      expect{ described_class.uname.debug }.not_to raise_error
      expect(described_class.uname.debug).to be(true).or be(false)
    end

    example "description" do
      expect{ described_class.uname.description }.not_to raise_error
      expect(described_class.uname.description).to be_kind_of(String)
    end

    example "distributed" do
      expect{ described_class.uname.distributed }.not_to raise_error
      expect(described_class.uname.distributed).to be(true).or be(false)
    end

    example "encryption_level" do
      expect{ described_class.uname.encryption_level }.not_to raise_error
      expect(described_class.uname.encryption_level).to be_kind_of(Integer)
    end

    example "foreground_application_boost" do
      expect{ described_class.uname.foreground_application_boost }.not_to raise_error
      expect(described_class.uname.foreground_application_boost).to be_kind_of(Integer)
    end

    example "free_physical_memory" do
      expect{ described_class.uname.free_physical_memory }.not_to raise_error
      expect(described_class.uname.free_physical_memory).to be_kind_of(Integer)
    end

    example "free_space_in_paging_files" do
      expect{ described_class.uname.free_space_in_paging_files }.not_to raise_error
      expect(described_class.uname.free_space_in_paging_files).to be_kind_of(Integer)
    end

    example "free_virtual_memory" do
      expect{ described_class.uname.free_virtual_memory}.not_to raise_error
      expect(described_class.uname.free_virtual_memory).to be_kind_of(Integer)
    end

    example "install_date" do
      expect{ described_class.uname.install_date}.not_to raise_error
      expect(described_class.uname.install_date).to be_kind_of(Time)
    end

    example "last_bootup_time" do
      expect{ described_class.uname.last_bootup_time}.not_to raise_error
      expect(described_class.uname.last_bootup_time).to be_kind_of(Time)
    end

    example "local_date_time" do
      expect{ described_class.uname.local_date_time}.not_to raise_error
      expect(described_class.uname.local_date_time).to be_kind_of(Time)
    end

    example "locale" do
      expect{ described_class.uname.locale}.not_to raise_error
      expect(described_class.uname.locale).to be_kind_of(String)
    end

    example "manufacturer" do
      expect{ described_class.uname.manufacturer}.not_to raise_error
      expect(described_class.uname.manufacturer).to be_kind_of(String)
    end

    example "max_number_of_processes" do
      expect{ described_class.uname.max_number_of_processes}.not_to raise_error
      expect(described_class.uname.max_number_of_processes).to be_kind_of(Integer)
    end

    example "max_process_memory_size" do
      expect{ described_class.uname.max_process_memory_size}.not_to raise_error
      expect(described_class.uname.max_process_memory_size).to be_kind_of(Integer)
    end

    example "name" do
      expect{ described_class.uname.name }.not_to raise_error
      expect(described_class.uname.name).to be_kind_of(String)
    end

    example "number_of_licensed_users" do
      expect{ described_class.uname.number_of_licensed_users }.not_to raise_error
      expect(described_class.uname.number_of_licensed_users).to be_kind_of(Integer).or be_nil
    end

    example "number_of_processes" do
      expect{ described_class.uname.number_of_processes }.not_to raise_error
      expect(described_class.uname.number_of_processes).to be_kind_of(Integer)
    end

    example "number_of_users" do
      expect{ described_class.uname.number_of_users }.not_to raise_error
      expect(described_class.uname.number_of_users).to be_kind_of(Integer)
    end

    example "organization" do
      expect{ described_class.uname.organization }.not_to raise_error
      expect(described_class.uname.organization).to be_kind_of(String)
    end

    example "os_language" do
      expect{ described_class.uname.os_language }.not_to raise_error
      expect(described_class.uname.os_language).to be_kind_of(Integer)
    end

    example "os_product_suite" do
      expect{ described_class.uname.os_product_suite }.not_to raise_error
      expect(described_class.uname.os_product_suite).to be_kind_of(Integer)
    end

    example "os_type" do
      expect{ described_class.uname.os_type }.not_to raise_error
      expect(described_class.uname.os_type).to be_kind_of(Integer)
    end

    example "other_type_description" do
      expect{ described_class.uname.other_type_description}.not_to raise_error
      expect(described_class.uname.other_type_description).to be_kind_of(String).or be_nil
    end

    example "plus_product_id" do
      expect{ described_class.uname.plus_product_id }.not_to raise_error
      expect(described_class.uname.plus_product_id).to be_kind_of(Integer).or be_nil
    end

    example "plus_version_number" do
      expect{ described_class.uname.plus_version_number }.not_to raise_error
      expect(described_class.uname.plus_version_number).to be_kind_of(Integer).or be_nil
    end

    example "primary" do
      expect{ described_class.uname.primary }.not_to raise_error
      expect(described_class.uname.primary).to eql(true).or eql(false)
    end

    example "product_type" do
      expect{ described_class.uname.product_type }.not_to raise_error
      expect(described_class.uname.product_type).to be_kind_of(Integer)
    end

    example "quantum_length" do
      expect{ described_class.uname.quantum_length }.not_to raise_error
      expect(described_class.uname.quantum_length).to be_kind_of(Integer).or be_nil
    end

    example "quantum_type" do
      expect{ described_class.uname.quantum_type }.not_to raise_error
      expect(described_class.uname.quantum_type).to be_kind_of(Integer).or be_nil
    end

    example "registered_user" do
      expect{ described_class.uname.registered_user }.not_to raise_error
      expect(described_class.uname.registered_user).to be_kind_of(String)
    end

    example "serial_number" do
      expect{ described_class.uname.serial_number }.not_to raise_error
      expect(described_class.uname.serial_number).to be_kind_of(String)
    end

    example "service_pack_major_version" do
      expect{ described_class.uname.service_pack_major_version }.not_to raise_error
      expect(described_class.uname.service_pack_major_version).to be_kind_of(Integer)
    end

    example "service_pack_minor_version" do
      expect{ described_class.uname.service_pack_minor_version }.not_to raise_error
      expect(described_class.uname.service_pack_minor_version).to be_kind_of(Integer)
    end

    example "status" do
      expect{ described_class.uname.status }.not_to raise_error
      expect(described_class.uname.status).to be_kind_of(String)
    end

    example "suite_mask" do
      expect{ described_class.uname.suite_mask }.not_to raise_error
      expect(described_class.uname.suite_mask).to be_kind_of(Integer)
    end

    example "system_device" do
      expect{ described_class.uname.system_device }.not_to raise_error
      expect(described_class.uname.system_device).to be_kind_of(String)
    end

    example "system_directory" do
      expect{ described_class.uname.system_directory }.not_to raise_error
      expect(described_class.uname.system_directory).to be_kind_of(String)
    end

    example "system_drive" do
      expect{ described_class.uname.system_drive }.not_to raise_error
      expect(described_class.uname.system_drive).to be_kind_of(String)
      expect(described_class.uname.system_drive).to eql("C:")
    end

    example "total_swap_space_size" do
      expect{ described_class.uname.total_swap_space_size }.not_to raise_error
      expect(described_class.uname.total_swap_space_size).to be_kind_of(Integer).or be_nil
    end

    example "total_virtual_memory_size" do
      expect{ described_class.uname.total_virtual_memory_size }.not_to raise_error
      expect(described_class.uname.total_virtual_memory_size).to be_kind_of(Integer)
    end

    example "total_visible_memory_size" do
      expect{ described_class.uname.total_visible_memory_size }.not_to raise_error
      expect(described_class.uname.total_visible_memory_size).to be_kind_of(Integer)
    end

    example "version" do
      expect{ described_class.uname.version }.not_to raise_error
      expect(described_class.uname.version).to be_kind_of(String)
    end

    example "windows_directory" do
      expect{ described_class.uname.windows_directory }.not_to raise_error
      expect(described_class.uname.windows_directory).to be_kind_of(String)
    end
  end
end
