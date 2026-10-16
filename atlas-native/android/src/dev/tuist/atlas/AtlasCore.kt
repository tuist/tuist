package dev.tuist.atlas

import android.net.Uri

data class AtlasSection(
    val title: String,
    val description: String,
    val url: String,
    val screen: String,
    val id: String,
    val group: String,
    val shortcut: Boolean,
    val requiredScope: String,
) {
    fun destination(server: String): Uri {
        val origin = Uri.parse(server)
        return Uri
            .parse(url)
            .buildUpon()
            .scheme(origin.scheme)
            .encodedAuthority(origin.encodedAuthority)
            .build()
    }
}

data class AtlasGroup(
    val title: String,
    val description: String,
    val id: String,
    val parent: String,
    val placement: String,
)

class AtlasCore {
    private external fun sectionCount(): Int

    private external fun fieldLength(
        section: Int,
        field: Int,
    ): Int

    private external fun fieldByte(
        section: Int,
        field: Int,
        offset: Int,
    ): Int

    private external fun groupCount(): Int

    private external fun groupFieldLength(
        group: Int,
        field: Int,
    ): Int

    private external fun groupFieldByte(
        group: Int,
        field: Int,
        offset: Int,
    ): Int

    fun sections(): List<AtlasSection> =
        List(sectionCount()) { section ->
            AtlasSection(
                readField(section, 0),
                readField(section, 1),
                readField(section, 2),
                readField(section, 3),
                readField(section, 4),
                readField(section, 5),
                readField(section, 6) == "1",
                readField(section, 7),
            )
        }

    fun groups(): List<AtlasGroup> =
        List(groupCount()) { group ->
            AtlasGroup(
                readField(group, 0, true),
                readField(group, 1, true),
                readField(group, 2, true),
                readField(group, 3, true),
                readField(group, 4, true),
            )
        }

    private fun readField(
        section: Int,
        field: Int,
        group: Boolean = false,
    ): String {
        val length = if (group) groupFieldLength(section, field) else fieldLength(section, field)
        check(length in 0..4096) { "Invalid Atlas core field length" }
        return ByteArray(length) { offset ->
            val byte = if (group) groupFieldByte(section, field, offset) else fieldByte(section, field, offset)
            check(byte in 0..255) { "Invalid Atlas core field byte" }
            byte.toByte()
        }.toString(Charsets.UTF_8)
    }

    companion object {
        init {
            System.loadLibrary("atlas_core")
        }
    }
}
