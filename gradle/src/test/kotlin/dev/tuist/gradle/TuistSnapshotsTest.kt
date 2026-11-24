package dev.tuist.gradle

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals

class TuistSnapshotsTest {
    @TempDir
    lateinit var directory: File

    @Test
    fun `collect reads Sentry-format metadata next to each image and skips the JSON files`() {
        png("Buttons.Primary.png")
        File(directory, "Buttons.Primary.json").writeText(
            """{"display_name":"Buttons.Primary","group":"Buttons","tags":{"ui_mode":"dark","font_scale":1.5},"diff_threshold":0.02,"context":{"class_name":"ButtonsKt"}}"""
        )
        png("nested/Card.png")
        File(directory, "nested/Card.json").writeText("""{"tags":["compact","rtl"]}""")
        png("Plain.png")
        png("Broken.png")
        File(directory, "Broken.json").writeText("{not json")

        val images = SnapshotImages.collect(directory).associateBy { it.name }

        assertEquals(listOf("Broken.png", "Buttons.Primary.png", "Plain.png", "nested/Card.png"), images.keys.toList())
        assertEquals(
            SnapshotMetadata("Buttons.Primary", "Buttons", mapOf("ui_mode" to "dark", "font_scale" to "1.5"), 0.02),
            images.getValue("Buttons.Primary.png").metadata
        )
        assertEquals(SnapshotMetadata(tags = mapOf("compact" to "true", "rtl" to "true")), images.getValue("nested/Card.png").metadata)
        assertEquals(SnapshotMetadata(), images.getValue("Plain.png").metadata)
        assertEquals(SnapshotMetadata(), images.getValue("Broken.png").metadata)
        assertEquals(3 to 2, images.getValue("Plain.png").width!! to images.getValue("Plain.png").height!!)
    }

    @Test
    fun `allImageNames reads the list the generated test writes, without blank lines or duplicates`() {
        assertEquals(null, SnapshotImages.allImageNames(directory))
        File(directory, SnapshotImages.ALL_IMAGE_NAMES_FILE).writeText("A.png\n\nB.png\nA.png\n")
        assertEquals(listOf("A.png", "B.png"), SnapshotImages.allImageNames(directory))
    }

    @Test
    fun `pullRequestTitle reads GitLab's variable, then GitHub's event payload`() {
        val event = File(directory, "event.json").apply {
            writeText("""{"pull_request":{"number":42,"title":"Refresh the \"brand\" color"}}""")
        }
        val push = File(directory, "push.json").apply { writeText("""{"ref":"refs/heads/main"}""") }

        assertEquals(
            "Refresh the \"brand\" color",
            SnapshotGitContext.pullRequestTitle(mapOf("GITHUB_EVENT_PATH" to event.path)::get)
        )
        assertEquals(
            "GitLab title",
            SnapshotGitContext.pullRequestTitle(mapOf("CI_MERGE_REQUEST_TITLE" to "GitLab title", "GITHUB_EVENT_PATH" to event.path)::get)
        )
        assertEquals(null, SnapshotGitContext.pullRequestTitle(mapOf("GITHUB_EVENT_PATH" to push.path)::get))
        assertEquals(null, SnapshotGitContext.pullRequestTitle(emptyMap<String, String>()::get))
    }

    private fun png(name: String) {
        val file = File(directory, name).apply { parentFile.mkdirs() }
        javax.imageio.ImageIO.write(java.awt.image.BufferedImage(3, 2, java.awt.image.BufferedImage.TYPE_INT_ARGB), "PNG", file)
    }
}
