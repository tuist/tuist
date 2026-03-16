package dev.tuist.gradle

import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.Pointer
import com.sun.jna.Structure
import com.sun.jna.ptr.IntByReference
import com.sun.jna.ptr.PointerByReference

/**
 * JNA bindings for macOS system APIs to collect network and disk I/O metrics
 * without spawning subprocesses.
 */

// --- Network metrics via getifaddrs / AF_LINK ---

private const val AF_LINK = 18

@Structure.FieldOrder(
    "ifi_type", "ifi_typelen", "ifi_physical", "ifi_addrlen", "ifi_hdrlen",
    "ifi_recvquota", "ifi_xmitquota", "ifi_unused1",
    "ifi_mtu", "ifi_metric", "ifi_baudrate",
    "ifi_ipackets", "ifi_ierrors", "ifi_opackets", "ifi_oerrors",
    "ifi_collisions", "ifi_ibytes", "ifi_obytes",
    "ifi_imcasts", "ifi_omcasts", "ifi_iqdrops", "ifi_noproto",
    "ifi_recvtiming", "ifi_xmittiming",
    "ifi_lastchange_tv_sec", "ifi_lastchange_tv_usec"
)
class IfData(p: Pointer) : Structure(p) {
    @JvmField var ifi_type: Byte = 0
    @JvmField var ifi_typelen: Byte = 0
    @JvmField var ifi_physical: Byte = 0
    @JvmField var ifi_addrlen: Byte = 0
    @JvmField var ifi_hdrlen: Byte = 0
    @JvmField var ifi_recvquota: Byte = 0
    @JvmField var ifi_xmitquota: Byte = 0
    @JvmField var ifi_unused1: Byte = 0
    @JvmField var ifi_mtu: Int = 0
    @JvmField var ifi_metric: Int = 0
    @JvmField var ifi_baudrate: Int = 0
    @JvmField var ifi_ipackets: Int = 0
    @JvmField var ifi_ierrors: Int = 0
    @JvmField var ifi_opackets: Int = 0
    @JvmField var ifi_oerrors: Int = 0
    @JvmField var ifi_collisions: Int = 0
    @JvmField var ifi_ibytes: Int = 0
    @JvmField var ifi_obytes: Int = 0
    @JvmField var ifi_imcasts: Int = 0
    @JvmField var ifi_omcasts: Int = 0
    @JvmField var ifi_iqdrops: Int = 0
    @JvmField var ifi_noproto: Int = 0
    @JvmField var ifi_recvtiming: Int = 0
    @JvmField var ifi_xmittiming: Int = 0
    @JvmField var ifi_lastchange_tv_sec: Int = 0
    @JvmField var ifi_lastchange_tv_usec: Int = 0

    init { read() }
}

@Structure.FieldOrder("sa_len", "sa_family", "sa_data")
class SockAddr(p: Pointer) : Structure(p) {
    @JvmField var sa_len: Byte = 0
    @JvmField var sa_family: Byte = 0
    @JvmField var sa_data: ByteArray = ByteArray(14)

    init { read() }
}

@Structure.FieldOrder("ifa_next", "ifa_name", "ifa_flags", "ifa_addr", "ifa_netmask", "ifa_dstaddr", "ifa_data")
class Ifaddrs(p: Pointer) : Structure(p) {
    @JvmField var ifa_next: Pointer? = null
    @JvmField var ifa_name: String? = null
    @JvmField var ifa_flags: Int = 0
    @JvmField var ifa_addr: Pointer? = null
    @JvmField var ifa_netmask: Pointer? = null
    @JvmField var ifa_dstaddr: Pointer? = null
    @JvmField var ifa_data: Pointer? = null

    init { read() }
}

// --- Disk metrics via IOKit ---

@Suppress("FunctionName")
private interface SystemLib : Library {
    fun getifaddrs(ifap: PointerByReference): Int
    fun freeifaddrs(ifa: Pointer)
}

@Suppress("FunctionName")
private interface IOKitLib : Library {
    fun IOServiceMatching(name: String): Pointer?
    fun IOServiceGetMatchingServices(mainPort: Int, matching: Pointer, existing: IntByReference): Int
    fun IOIteratorNext(iterator: Int): Int
    fun IORegistryEntryCreateCFProperties(
        entry: Int,
        properties: PointerByReference,
        allocator: Pointer?,
        options: Int
    ): Int
    fun IOObjectRelease(obj: Int): Int
}

@Suppress("FunctionName")
private interface CoreFoundationLib : Library {
    fun CFDictionaryGetValue(dict: Pointer, key: Pointer): Pointer?
    fun CFDictionaryGetCount(dict: Pointer): Int
    fun CFGetTypeID(cf: Pointer): Long
    fun CFDictionaryGetTypeID(): Long
    fun CFNumberGetTypeID(): Long
    fun CFNumberGetValue(number: Pointer, theType: Int, valuePtr: Pointer): Boolean
    fun CFRelease(cf: Pointer)
    fun CFStringCreateWithCString(alloc: Pointer?, cStr: String, encoding: Int): Pointer
}

private const val KERN_SUCCESS = 0
private const val kCFStringEncodingUTF8 = 0x08000100
private const val kCFNumberSInt64Type = 4
private const val kIOMainPortDefault = 0

object MacOSSystemMetrics {
    private val systemLib: SystemLib? = try {
        Native.load("System", SystemLib::class.java)
    } catch (e: Throwable) { null }

    private val ioKit: IOKitLib? = try {
        Native.load("IOKit", IOKitLib::class.java)
    } catch (e: Throwable) { null }

    private val cf: CoreFoundationLib? = try {
        Native.load("CoreFoundation", CoreFoundationLib::class.java)
    } catch (e: Throwable) { null }

    val isAvailable: Boolean get() = systemLib != null && ioKit != null && cf != null

    fun readNetworkBytes(): Pair<Long, Long> {
        val lib = systemLib ?: return Pair(0L, 0L)
        val ptrRef = PointerByReference()
        if (lib.getifaddrs(ptrRef) != 0) return Pair(0L, 0L)

        var totalIn = 0L
        var totalOut = 0L

        try {
            var ptr = ptrRef.value
            while (ptr != null) {
                val ifaddrs = Ifaddrs(ptr)

                val addrPtr = ifaddrs.ifa_addr
                if (addrPtr != null) {
                    val sockAddr = SockAddr(addrPtr)

                    if (sockAddr.sa_family.toInt() and 0xFF == AF_LINK && ifaddrs.ifa_data != null) {
                        val ifData = IfData(ifaddrs.ifa_data!!)
                        totalIn += ifData.ifi_ibytes.toLong() and 0xFFFFFFFFL
                        totalOut += ifData.ifi_obytes.toLong() and 0xFFFFFFFFL
                    }
                }
                ptr = ifaddrs.ifa_next
            }
        } finally {
            lib.freeifaddrs(ptrRef.value)
        }

        return Pair(totalIn, totalOut)
    }

    fun readDiskBytes(): Pair<Long, Long> {
        val ioKit = ioKit ?: return Pair(0L, 0L)
        val cf = cf ?: return Pair(0L, 0L)

        val matching = ioKit.IOServiceMatching("IOBlockStorageDriver") ?: return Pair(0L, 0L)
        val iteratorRef = IntByReference()
        if (ioKit.IOServiceGetMatchingServices(kIOMainPortDefault, matching, iteratorRef) != KERN_SUCCESS) {
            return Pair(0L, 0L)
        }
        val iterator = iteratorRef.value

        var totalRead = 0L
        var totalWritten = 0L

        val statisticsKey = cf.CFStringCreateWithCString(null, "Statistics", kCFStringEncodingUTF8)
        val bytesReadKey = cf.CFStringCreateWithCString(null, "Bytes (Read)", kCFStringEncodingUTF8)
        val bytesWrittenKey = cf.CFStringCreateWithCString(null, "Bytes (Write)", kCFStringEncodingUTF8)

        try {
            var service = ioKit.IOIteratorNext(iterator)
            while (service != 0) {
                val propsRef = PointerByReference()
                if (ioKit.IORegistryEntryCreateCFProperties(service, propsRef, null, 0) == KERN_SUCCESS) {
                    val propsDict = propsRef.value
                    val statsDict = cf.CFDictionaryGetValue(propsDict, statisticsKey)

                    if (statsDict != null) {
                        val readVal = cf.CFDictionaryGetValue(statsDict, bytesReadKey)
                        if (readVal != null) {
                            totalRead += cfNumberToLong(cf, readVal)
                        }
                        val writeVal = cf.CFDictionaryGetValue(statsDict, bytesWrittenKey)
                        if (writeVal != null) {
                            totalWritten += cfNumberToLong(cf, writeVal)
                        }
                    }
                    cf.CFRelease(propsDict)
                }
                ioKit.IOObjectRelease(service)
                service = ioKit.IOIteratorNext(iterator)
            }
        } finally {
            ioKit.IOObjectRelease(iterator)
            cf.CFRelease(statisticsKey)
            cf.CFRelease(bytesReadKey)
            cf.CFRelease(bytesWrittenKey)
        }

        return Pair(totalRead, totalWritten)
    }

    private fun cfNumberToLong(cf: CoreFoundationLib, cfNumber: Pointer): Long {
        val buf = com.sun.jna.Memory(8)
        return if (cf.CFNumberGetValue(cfNumber, kCFNumberSInt64Type, buf)) {
            buf.getLong(0)
        } else {
            0L
        }
    }
}
