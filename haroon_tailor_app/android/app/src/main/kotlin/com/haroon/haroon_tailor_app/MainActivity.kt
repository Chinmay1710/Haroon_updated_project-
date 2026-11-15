package com.haroon.haroon_tailor_app

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.File
import java.io.FileReader
import java.io.FileWriter

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "HaroonMainActivity"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Pre-startup sanitization of SharedPreferences to prevent 300MB OOM crash
        sanitizeSharedPreferences()
        super.onCreate(savedInstanceState)
    }

    private fun sanitizeSharedPreferences() {
        try {
            val sharedPrefsDir = File(applicationInfo.dataDir, "shared_prefs")
            val prefsFile = File(sharedPrefsDir, "FlutterSharedPreferences.xml")
            val bakFile = File(sharedPrefsDir, "FlutterSharedPreferences.xml.bak")

            if (prefsFile.exists() && prefsFile.length() > 200_000) { // > 200KB
                Log.i(TAG, "Sanitizing oversized SharedPreferences file: ${prefsFile.length()} bytes")
                cleanXmlFile(prefsFile)
            }
            if (bakFile.exists() && bakFile.length() > 200_000) {
                bakFile.delete()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error sanitizing SharedPreferences: ${e.message}", e)
        }
    }

    private fun cleanXmlFile(file: File) {
        val tempFile = File(file.parentFile, "${file.name}.tmp")
        try {
            val reader = BufferedReader(FileReader(file), 65536)
            val writer = BufferedWriter(FileWriter(tempFile), 65536)

            var inSkippedTag = false
            val tagBuffer = StringBuilder()
            var ch = reader.read()

            while (ch != -1) {
                val c = ch.toChar()
                if (!inSkippedTag) {
                    if (c == '<') {
                        tagBuffer.setLength(0)
                        tagBuffer.append(c)
                        while (ch != -1) {
                            ch = reader.read()
                            if (ch != -1) {
                                val nextC = ch.toChar()
                                tagBuffer.append(nextC)
                                if (nextC == '>') break
                                if (tagBuffer.length > 500) break
                            }
                        }
                        val tagStr = tagBuffer.toString()
                        // Skip huge cache collections, keep starting_bill_number, paper size, theme, etc.
                        if (tagStr.startsWith("<string") && (
                                tagStr.contains("name=\"flutter.ht_cache_") ||
                                tagStr.contains("name=\"ht_cache_")
                            )) {
                            if (!tagStr.endsWith("/>")) {
                                inSkippedTag = true
                            }
                        } else {
                            writer.write(tagStr)
                        }
                    } else {
                        writer.write(ch)
                    }
                } else {
                    if (c == '<') {
                        tagBuffer.setLength(0)
                        tagBuffer.append(c)
                        while (ch != -1) {
                            ch = reader.read()
                            if (ch != -1) {
                                val nextC = ch.toChar()
                                tagBuffer.append(nextC)
                                if (nextC == '>') break
                                if (tagBuffer.length > 50) break
                            }
                        }
                        if (tagBuffer.toString() == "</string>") {
                            inSkippedTag = false
                        }
                    }
                }
                ch = reader.read()
            }

            reader.close()
            writer.flush()
            writer.close()

            if (tempFile.length() > 0) {
                val bakFile = File(file.parentFile, "${file.name}.bak")
                if (bakFile.exists()) bakFile.delete()
                file.delete()
                tempFile.renameTo(file)
                Log.i(TAG, "Sanitization complete. New file size: ${file.length()} bytes")
            } else {
                tempFile.delete()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed cleaning XML: ${e.message}", e)
            if (tempFile.exists()) tempFile.delete()
        }
    }
}
