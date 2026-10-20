package dev.tuist.gradle

import java.io.File
import java.nio.channels.FileChannel
import java.nio.file.StandardOpenOption

/** Holds an exclusive lock on the file named by its argument until its stdin closes, as another Gradle process would. */
object FileLockHolder {
    @JvmStatic
    fun main(args: Array<String>) {
        FileChannel.open(File(args[0]).toPath(), StandardOpenOption.CREATE, StandardOpenOption.WRITE).use { channel ->
            channel.lock().use {
                println("locked")
                System.out.flush()
                System.`in`.read()
            }
        }
    }

    /** Starts a process holding the lock and returns once it holds it. */
    fun start(lockFile: File): Process {
        val java = ProcessHandle.current().info().command().get()
        val process = ProcessBuilder(
            java, "-cp", System.getProperty("java.class.path"), FileLockHolder::class.java.name, lockFile.path
        ).redirectErrorStream(true).start()
        val line = process.inputStream.bufferedReader().readLine()
        check(line == "locked") { "The lock holder did not take the lock: $line" }
        return process
    }
}
