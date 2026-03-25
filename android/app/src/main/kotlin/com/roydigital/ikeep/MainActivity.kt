package com.roydigital.ikeep

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import com.mr.flutter.plugin.filepicker.FilePickerPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val invoicePickerChannel = "ikeep/native_invoice_picker"
        private const val itemInvoicesDir = "item_invoices"
        private const val sharedInvoicesDir = "shared_invoices"
        private const val invoicePickerRequestCode = 41011
    }

    private var pendingInvoicePickerResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (!flutterEngine.plugins.has(FilePickerPlugin::class.java)) {
            flutterEngine.plugins.add(FilePickerPlugin())
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            invoicePickerChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickInvoice" -> launchInvoicePicker(result)
                "openInvoice" -> openInvoice(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun openInvoice(call: MethodCall, result: MethodChannel.Result) {
        val invoicePath = call.argument<String>("path")?.trim().orEmpty()
        if (invoicePath.isEmpty()) {
            result.error("invoice_path_missing", "Invoice path is required.", null)
            return
        }

        val invoiceFile = File(invoicePath)
        if (!invoiceFile.exists()) {
            result.error("invoice_missing", "Invoice file was not found.", null)
            return
        }

        try {
            val shareableInvoiceFile = prepareInvoiceForSharing(invoiceFile)
            val invoiceUri = FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.fileprovider",
                shareableInvoiceFile,
            )
            val openIntent =
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(invoiceUri, resolveMimeType(shareableInvoiceFile))
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            val chooserIntent = Intent.createChooser(openIntent, "Open invoice").apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            startActivity(chooserIntent)
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            result.success(false)
        } catch (error: Exception) {
            result.error(
                "invoice_open_failed",
                error.message ?: "Could not open this invoice.",
                null,
            )
        }
    }

    @Deprecated("Deprecated in Activity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != invoicePickerRequestCode) {
            return
        }

        val result = pendingInvoicePickerResult
        pendingInvoicePickerResult = null

        if (result == null) {
            return
        }

        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }

        val uri = data?.data
        if (uri == null) {
            result.success(null)
            return
        }

        try {
            result.success(copyInvoiceToInternalStorage(uri))
        } catch (error: Exception) {
            result.error(
                "invoice_picker_failed",
                error.message ?: "Could not attach this invoice.",
                null,
            )
        }
    }

    private fun launchInvoicePicker(result: MethodChannel.Result) {
        if (pendingInvoicePickerResult != null) {
            result.error(
                "invoice_picker_busy",
                "Another invoice picker request is already active.",
                null,
            )
            return
        }

        pendingInvoicePickerResult = result

        try {
            val intent =
                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                }
            startActivityForResult(intent, invoicePickerRequestCode)
        } catch (error: Exception) {
            pendingInvoicePickerResult = null
            result.error(
                "invoice_picker_unavailable",
                error.message ?: "Could not open the invoice picker.",
                null,
            )
        }
    }

    private fun copyInvoiceToInternalStorage(uri: Uri): Map<String, Any> {
        val originalName = resolveInvoiceName(uri)
        val extension = originalName.substringAfterLast('.', "")
        val baseName =
            if (extension.isBlank()) {
                originalName
            } else {
                originalName.removeSuffix(".$extension")
            }
        val safeBaseName = sanitizeFileName(baseName).ifBlank { "invoice" }
        val safeExtension = sanitizeFileName(extension)
        val targetName =
            buildString {
                append(System.currentTimeMillis())
                append('_')
                append(safeBaseName)
                if (safeExtension.isNotBlank()) {
                    append('.')
                    append(safeExtension)
                }
            }

        val invoicesDir = File(filesDir, itemInvoicesDir)
        if (!invoicesDir.exists() && !invoicesDir.mkdirs()) {
            throw IllegalStateException("Could not prepare invoice storage.")
        }

        val targetFile = File(invoicesDir, targetName)
        contentResolver.openInputStream(uri)?.use { inputStream ->
            FileOutputStream(targetFile).use { outputStream ->
                inputStream.copyTo(outputStream)
            }
        } ?: throw IllegalStateException("Selected invoice could not be read.")

        return mapOf(
            "path" to targetFile.absolutePath,
            "fileName" to originalName,
            "sizeBytes" to targetFile.length().toInt(),
        )
    }

    private fun prepareInvoiceForSharing(sourceFile: File): File {
        val shareDir = File(cacheDir, sharedInvoicesDir)
        if (!shareDir.exists() && !shareDir.mkdirs()) {
            throw IllegalStateException("Could not prepare shared invoice cache.")
        }

        val targetFile = File(shareDir, sourceFile.name)
        if (targetFile.exists() && !targetFile.delete()) {
            throw IllegalStateException("Could not refresh shared invoice copy.")
        }

        sourceFile.copyTo(targetFile, overwrite = true)
        return targetFile
    }

    private fun resolveInvoiceName(uri: Uri): String {
        val displayName =
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIndex >= 0 && cursor.moveToFirst()) {
                        cursor.getString(nameIndex)
                    } else {
                        null
                    }
                }

        val trimmedName = displayName?.trim().orEmpty()
        if (trimmedName.isNotEmpty()) {
            return trimmedName
        }

        val fallbackName = uri.lastPathSegment?.substringAfterLast('/')?.trim().orEmpty()
        return if (fallbackName.isNotEmpty()) fallbackName else "invoice"
    }

    private fun sanitizeFileName(value: String): String =
        value
            .replace(Regex("[^A-Za-z0-9._-]+"), "_")
            .replace(Regex("_+"), "_")
            .trim('_', '.')

    private fun resolveMimeType(file: File): String {
        val extension = file.extension.lowercase()
        if (extension.isBlank()) {
            return "*/*"
        }

        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "*/*"
    }
}
