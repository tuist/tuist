package dev.tuist.gradle

import java.io.File

/** Holds an exclusive lock on the file named by its argument until its stdin closes, as another Gradle process would. */
object FileLockHolder {
    @JvmStatic
    fun main(args: Array<String>) {
        CachedValueStore<String>(lockFilePath = File(args[0])).getValue {
            println("locked")
            System.out.flush()
            System.`in`.read()
            Pair("released", null)
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
