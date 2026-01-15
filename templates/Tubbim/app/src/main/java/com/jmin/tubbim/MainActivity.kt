package com.jmin.tubbim

import androidx.activity.result.contract.ActivityResultContracts
import android.webkit.ValueCallback
import android.net.Uri
import android.content.Intent
import android.app.Activity
import android.annotation.SuppressLint
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import android.widget.Toast
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.jmin.tubbim.utils.AppConfig
import com.jmin.tubbim.utils.SystemBarsConfig


class MainActivity : AppCompatActivity() {
    private lateinit var webView: WebView
    private var lastBackPressAt: Long = 0L
    private var filePathCallback: ValueCallback<Array<Uri>>? = null
    private val fileChooserLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val callback = filePathCallback
        if (callback == null) return@registerForActivityResult
        val uris = if (result.resultCode == Activity.RESULT_OK) {
            val data = result.data
            val clipData = data?.clipData
            when {
                clipData != null -> Array(clipData.itemCount) { idx -> clipData.getItemAt(idx).uri }
                data?.data != null -> arrayOf(data.data!!)
                else -> emptyArray()
            }
        } else {
            emptyArray()
        }
        callback.onReceiveValue(uris)
        filePathCallback = null
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applySystemBarsConfig(AppConfig.systemBars)

        // 创建WebView
        webView = WebView(this)
        setContentView(webView)

        // 配置WebView设置
        val webSettings: WebSettings = webView.settings
        webSettings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            javaScriptCanOpenWindowsAutomatically = true
            loadWithOverviewMode = true
            useWideViewPort = true
            builtInZoomControls = false
            displayZoomControls = false
            setSupportZoom(false)
            cacheMode = WebSettings.LOAD_DEFAULT
            allowFileAccess = true
            allowContentAccess = true
            mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
        }

        // 设置WebViewClient和WebChromeClient
        webView.apply {
            webViewClient = WebViewClient()
            webChromeClient = object : WebChromeClient() {
                override fun onShowFileChooser(
                    webView: WebView?,
                    filePathCallback: ValueCallback<Array<Uri>>?,
                    fileChooserParams: FileChooserParams?
                ): Boolean {
                    this@MainActivity.filePathCallback?.onReceiveValue(null)
                    this@MainActivity.filePathCallback = filePathCallback
                    val acceptTypes = fileChooserParams?.acceptTypes
                        ?.mapNotNull { it?.trim() }
                        ?.filter { it.isNotEmpty() }
                        ?: emptyList()
                    val allowMultiple = fileChooserParams?.mode == FileChooserParams.MODE_OPEN_MULTIPLE
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        type = if (acceptTypes.size == 1) acceptTypes[0] else "*/*"
                        if (acceptTypes.size > 1) {
                            putExtra(Intent.EXTRA_MIME_TYPES, acceptTypes.toTypedArray())
                        }
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple)
                    }
                    val chooserTitle = fileChooserParams?.title ?: "????"
                    val chooser = Intent.createChooser(intent, chooserTitle)
                    return try {
                        fileChooserLauncher.launch(chooser)
                        true
                    } catch (e: Exception) {
                        this@MainActivity.filePathCallback = null
                        false
                    }
                }
            }
            // 加载H5游戏地址
            loadUrl(AppConfig.webViewUrl)
        }

        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    if (::webView.isInitialized && webView.canGoBack()) {
                        webView.goBack()
                        return
                    }
                    if (!AppConfig.doubleClickExit) {
                        finish()
                        return
                    }
                    val now = System.currentTimeMillis()
                    if (now - lastBackPressAt <= 2000) {
                        finish()
                    } else {
                        lastBackPressAt = now
                        Toast.makeText(this@MainActivity, "再按一次退出应用", Toast.LENGTH_SHORT).show()
                    }
                }
            }
        )
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            applySystemBarsConfig(AppConfig.systemBars)
        }
    }

    override fun onDestroy() {
        webView.destroy()
        super.onDestroy()
    }

    private fun applySystemBarsConfig(config: SystemBarsConfig) {
        // 透明状态栏一般需要“内容绘制到状态栏下方”
        WindowCompat.setDecorFitsSystemWindows(window, !config.drawBehindStatusBar)

        @Suppress("DEPRECATION")
        window.statusBarColor = config.statusBarColor

        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.isAppearanceLightStatusBars = config.lightStatusBarIcons

        if (config.hideStatusBar) {
            window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
            window.clearFlags(WindowManager.LayoutParams.FLAG_FORCE_NOT_FULLSCREEN)
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.hide(WindowInsetsCompat.Type.statusBars())
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
            window.addFlags(WindowManager.LayoutParams.FLAG_FORCE_NOT_FULLSCREEN)
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility =
                if (config.lightStatusBarIcons) {
                    View.SYSTEM_UI_FLAG_VISIBLE or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
                } else {
                    View.SYSTEM_UI_FLAG_VISIBLE
                }
            controller.show(WindowInsetsCompat.Type.statusBars())
        }
    }
}