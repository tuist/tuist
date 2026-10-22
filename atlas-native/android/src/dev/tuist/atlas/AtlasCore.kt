package dev.tuist.atlas

data class AtlasSection(
    val title: String,
    val description: String,
    val url: String,
    val kind: String,
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

    fun sections(): List<AtlasSection> =
        List(sectionCount()) { section ->
            AtlasSection(readField(section, 0), readField(section, 1), readField(section, 2), readField(section, 3))
        }

    private fun readField(
        section: Int,
        field: Int,
    ): String {
        val length = fieldLength(section, field)
        check(length in 0..4096) { "Invalid Atlas core field length" }
        return ByteArray(length) { offset ->
            val byte = fieldByte(section, field, offset)
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
