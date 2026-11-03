package dev.tuist.gradle

import com.android.apksig.ApkVerifier
import com.android.apksig.internal.apk.AndroidBinXmlParser
import org.gradle.api.Action
import org.gradle.api.DefaultTask
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.Directory
import org.gradle.api.provider.Property
import org.gradle.api.provider.Provider
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputDirectory
import org.gradle.api.tasks.Internal
import org.gradle.api.tasks.Optional
import org.gradle.api.tasks.TaskAction
import org.gradle.api.tasks.options.Option
import org.gradle.language.cpp.CppApplication
import org.gradle.language.cpp.CppExecutable
import org.gradle.language.swift.SwiftApplication
import org.gradle.language.swift.SwiftExecutable
import org.gradle.language.nativeplatform.ComponentWithInstallation
import org.gradle.work.DisableCachingByDefault
import java.io.File
import java.nio.ByteBuffer
import java.util.zip.ZipFile

/** No hooks on assemble/build: requesting a share task is the publication consent. */
class TuistPreviewsPlugin : Plugin<Project> {
    override fun apply(project: Project) {
        project.pluginManager.withPlugin("com.android.application") {
            configureAndroid(project)
        }
        project.pluginManager.withPlugin("cpp-application") {
            project.extensions.getByType(CppApplication::class.java).binaries
                .whenElementFinalized(CppExecutable::class.java) { configureNative(project, name, this) }
        }
        project.pluginManager.withPlugin("swift-application") {
            project.extensions.getByType(SwiftApplication::class.java).binaries
                .whenElementFinalized(SwiftExecutable::class.java) { configureNative(project, name, this) }
        }
    }

    private fun configureNative(project: Project, name: String, binary: ComponentWithInstallation) {
        val config = TuistGradleConfig.from(project) ?: return
        project.tasks.register("tuistShare${name.replaceFirstChar { it.uppercaseChar() }}", TuistShareExecutable::class.java) {
            group = "tuist"
            description = "Build and publish the $name native distribution as a Tuist preview."
            distribution.set(binary.installTask.flatMap { it.installDirectory })
            nativeExecutable.set(binary.installTask.flatMap { it.installedExecutable })
            launcher.set(binary.installTask.flatMap { it.runScriptFile })
            serverUrl.set(config.url)
            config.project?.let { tuistProject.set(it) }
            useEnvironmentProxy.set(config.network.proxy)
            projectDirectory.set(project.layout.projectDirectory)
            publicationTarget.set("gradle:${project.path}:$name")
        }
    }

    private fun configureAndroid(project: Project) {
        val config = TuistGradleConfig.from(project) ?: return
        // AGP lives in the project's child classloader, not the settings plugin's loader.
        // Call its public variant API without bundling/pinning AGP into every Tuist project.
        val android = project.extensions.getByName("androidComponents")
        val selector = android.androidCall("selector").androidCall("all")
        android.androidCall("onVariants", selector, Action<Any> {
            val variant = this
            val name = variant.androidCall("getName") as String
            val artifacts = variant.androidCall("getArtifacts")
            val apk = android.javaClass.classLoader.loadClass("com.android.build.api.artifact.SingleArtifact\$APK")
                .getField("INSTANCE").get(null)
            @Suppress("UNCHECKED_CAST")
            val directory = artifacts.androidCall("get", apk) as Provider<Directory>
            project.tasks.register(
                "tuistShare${name.replaceFirstChar { it.uppercaseChar() }}",
                TuistSharePreview::class.java
            ) {
                group = "tuist"
                description = "Build and publish the $name application as a Tuist preview."
                apkDirectory.set(directory)
                artifactsLoader.set(artifacts.androidCall("getBuiltArtifactsLoader"))
                serverUrl.set(config.url)
                config.project?.let { tuistProject.set(it) }
                useEnvironmentProxy.set(config.network.proxy)
                projectDirectory.set(project.layout.projectDirectory)
                publicationTarget.set("gradle:${project.path}:$name")
            }
        })
    }
}

private fun Any.androidCall(name: String, vararg arguments: Any): Any =
    javaClass.methods.first { method ->
        method.name == name && method.parameterTypes.size == arguments.size &&
            method.parameterTypes.zip(arguments).all { (type, argument) -> type.isInstance(argument) }
    }.invoke(this, *arguments) ?: Unit

@DisableCachingByDefault(because = "Publication is an explicit side effect, deduplicated by server receipts")
abstract class TuistSharePreview : DefaultTask() {
    @get:InputDirectory abstract val apkDirectory: DirectoryProperty
    @get:Internal abstract val artifactsLoader: Property<Any>
    @get:Internal abstract val projectDirectory: DirectoryProperty
    @get:Input abstract val serverUrl: Property<String>
    @get:Input @get:Optional abstract val tuistProject: Property<String>
    @get:Input abstract val useEnvironmentProxy: Property<Boolean>
    @get:Input abstract val publicationTarget: Property<String>
    @get:Input @get:Optional abstract val track: Property<String>

    @Option(option = "track", description = "Publish to this preview track")
    fun track(value: String) { track.set(value) }

    @TaskAction
    fun share() {
        val artifacts = artifactsLoader.get().androidCall("load", apkDirectory.get())
        val output = (artifacts.androidCall("getElements") as Collection<*>).singleOrNull()
        require(output != null && (output.androidCall("getFilters") as Collection<*>).isEmpty()) {
            "Tuist previews require a single universal APK. Split APKs are not supported."
        }
        // Freeze the exact bytes before signature verification; no keys or other outputs are uploaded.
        val snapshot = File(temporaryDir, "application.apk")
        File(output.androidCall("getOutputFile") as String).copyTo(snapshot, overwrite = true)
        try {
            val verified = ApkVerifier.Builder(snapshot).build().verify()
            require(verified.isVerified && verified.signerCertificates.isNotEmpty()) {
                "The APK is unsigned or its signature is invalid. Configure Android signing before sharing."
            }
            // Use the same pinned parser as signature verification, not presentation-format SDK output.
            ZipFile(snapshot).use { zip ->
                val manifest = zip.getInputStream(zip.getEntry("AndroidManifest.xml")).use { it.readBytes() }
                val parser = AndroidBinXmlParser(ByteBuffer.wrap(manifest))
                while (parser.next() != AndroidBinXmlParser.EVENT_END_DOCUMENT) {
                    require(parser.eventType != AndroidBinXmlParser.EVENT_START_ELEMENT || parser.name != "instrumentation") {
                        "Instrumentation APKs are not application previews."
                    }
                }
            }
            val metadata = mapOf(
                "schema" to "once.android_application.v1",
                "application_id" to artifacts.androidCall("getApplicationId"),
                "version_code" to output.androidCall("getVersionCode").toString(),
                "version_name" to output.javaClass.getMethod("getVersionName").invoke(output),
                "certificate_sha256" to verified.signerCertificates.map { ArtifactPublisher.hexDigest(it.encoded) },
                "signature_verified" to true
            )
            val httpClients = TuistHttpClients(useEnvironmentProxy = useEnvironmentProxy.get())
            val publisher = ArtifactPublisher(
                ServerConfigurationProvider(tuistProject.orNull, serverUrl.get(), projectDirectory.get().asFile, httpClients),
                httpClients
            )
            val status = publisher.publish(snapshot, metadata, publicationTarget.get(), track.orNull)
            logger.lifecycle("Tuist: $status. Preview processing is asynchronous; open your project's Previews page.")
        } finally {
            snapshot.delete()
        }
    }
}
