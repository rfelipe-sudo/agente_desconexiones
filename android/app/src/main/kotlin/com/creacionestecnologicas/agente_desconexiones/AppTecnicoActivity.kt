package com.creacionestecnologicas.agente_desconexiones

import android.annotation.SuppressLint
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.webkit.JavascriptInterface
import android.webkit.JsPromptResult
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import org.json.JSONArray
import org.json.JSONObject

/**
 * WebView nativo en proceso separado para no bloquear Flutter (evita ANR en CREABOX).
 * Carga la app Ionic servida en http://127.0.0.1 desde Dart.
 */
class AppTecnicoActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private var loadingOverlay: View? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var bridgeSecret = 1
    private var autoUsername: String? = null
    private var autoPassword: String? = null
    private var autologinEnabled = false
    private var autologinAttempts = 0
    private var credentialsErrorShown = false
    private var autologinFinished = false

    private val autologinRunnable = object : Runnable {
        override fun run() {
            if (!::webView.isInitialized || autologinFinished || credentialsErrorShown) return
            if (autoUsername.isNullOrBlank() || autoPassword.isNullOrBlank()) return
            if (autologinAttempts >= 40) {
                onCredentialsError()
                return
            }
            autologinAttempts++
            injectAutologin(webView)
            mainHandler.postDelayed(this, 1500)
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        supportActionBar?.title = "App Técnico"
        supportActionBar?.setDisplayHomeAsUpEnabled(true)

        val root = FrameLayout(this)
        webView = WebView(this)
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            allowFileAccess = true
            allowContentAccess = true
            mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            cacheMode = WebSettings.LOAD_DEFAULT
            mediaPlaybackRequiresUserGesture = false
        }

        webView.addJavascriptInterface(CordovaNativeBridge(), "_cordovaNative")
        webView.addJavascriptInterface(AutologinBridge(), "CreaboxAutologin")

        webView.webChromeClient = object : WebChromeClient() {
            override fun onJsPrompt(
                view: WebView?,
                url: String?,
                message: String?,
                defaultValue: String?,
                result: JsPromptResult?,
            ): Boolean {
                if (result == null) return false
                val cordovaMsg = listOfNotNull(defaultValue, message)
                    .firstOrNull { it.startsWith("gap") }
                    ?: return false

                return handleCordovaMessage(view, cordovaMsg, result)
            }

            override fun onConsoleMessage(consoleMessage: android.webkit.ConsoleMessage?): Boolean {
                consoleMessage?.let {
                    Log.d(
                        TAG,
                        "JS ${it.messageLevel()}: ${it.message()} @ ${it.sourceId()}:${it.lineNumber()}",
                    )
                }
                return true
            }
        }

        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                injectCordovaBootstrap(view)
                mainHandler.postDelayed({ injectCordovaBootstrap(view) }, 500)
                mainHandler.postDelayed({ injectCordovaBootstrap(view) }, 2000)
                scheduleAutologin()
            }

            @Deprecated("Deprecated in Java")
            override fun onReceivedError(
                view: WebView?,
                errorCode: Int,
                description: String?,
                failingUrl: String?,
            ) {
                super.onReceivedError(view, errorCode, description, failingUrl)
                Log.e(TAG, "WebView error $errorCode on $failingUrl: $description")
            }
        }

        root.addView(
            webView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        loadingOverlay = buildLoadingOverlay()
        root.addView(
            loadingOverlay,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        setContentView(root)

        val url = intent.getStringExtra(EXTRA_URL)
        if (url.isNullOrBlank()) {
            finish()
            return
        }
        autoUsername = intent.getStringExtra(EXTRA_AUTO_USERNAME)?.trim()?.ifBlank { null }
        autoPassword = intent.getStringExtra(EXTRA_AUTO_PASSWORD)?.ifBlank { null }
        autologinEnabled = !autoUsername.isNullOrBlank() && !autoPassword.isNullOrBlank()
        if (autologinEnabled) {
            showLoadingOverlay(true)
            Log.i(TAG, "Autologin App Técnico habilitado para usuario ${autoUsername!!.take(3)}***")
        } else {
            showLoadingOverlay(false)
        }
        Log.i(TAG, "Cargando App Técnico: $url")
        webView.loadUrl(url)
    }

    private fun buildLoadingOverlay(): View {
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#FF0A1628"))
            setPadding(48, 48, 48, 48)
        }

        val spinner = ProgressBar(this).apply {
            isIndeterminate = true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                indeterminateTintList =
                    android.content.res.ColorStateList.valueOf(Color.parseColor("#FFE30613"))
            }
        }
        container.addView(spinner)

        val title = TextView(this).apply {
            text = "Cargando App Técnico…"
            setTextColor(Color.WHITE)
            textSize = 20f
            gravity = Gravity.CENTER
            setPadding(0, 36, 0, 12)
        }
        container.addView(title)

        val subtitle = TextView(this).apply {
            text = "Ingresando con tus credenciales CREA.\nEsto puede tardar unos segundos."
            setTextColor(Color.parseColor("#FF8FA8C8"))
            textSize = 13f
            gravity = Gravity.CENTER
        }
        container.addView(subtitle)

        return container
    }

    private fun showLoadingOverlay(show: Boolean) {
        loadingOverlay?.visibility = if (show) View.VISIBLE else View.GONE
    }

    private fun scheduleAutologin() {
        if (!autologinEnabled || autologinFinished || credentialsErrorShown) return
        mainHandler.removeCallbacks(autologinRunnable)
        autologinAttempts = 0
        mainHandler.postDelayed(autologinRunnable, 1200)
    }

    private fun onAutologinSuccess() {
        if (autologinFinished) return
        autologinFinished = true
        mainHandler.removeCallbacks(autologinRunnable)
        showLoadingOverlay(false)
        Log.i(TAG, "Autologin App Técnico OK")
    }

    private fun onCredentialsError() {
        if (credentialsErrorShown || autologinFinished) return
        credentialsErrorShown = true
        autologinFinished = true
        mainHandler.removeCallbacks(autologinRunnable)
        showLoadingOverlay(false)
        autoUsername = null
        autoPassword = null

        AlertDialog.Builder(this)
            .setMessage("ERROR EN TUS CREDENCIALES CONTACTA A SOPORTE CREA")
            .setCancelable(false)
            .setPositiveButton("Aceptar") { _, _ ->
                setResult(RESULT_CREDENTIALS_ERROR)
                finish()
            }
            .show()
    }

    private inner class AutologinBridge {
        @JavascriptInterface
        fun onStatus(status: String) {
            mainHandler.post {
                when (status) {
                    "success" -> onAutologinSuccess()
                    "credentials_error" -> onCredentialsError()
                }
            }
        }
    }

    private fun injectAutologin(view: WebView?) {
        if (view == null) return
        val user = autoUsername ?: return
        val pass = autoPassword ?: return
        view.evaluateJavascript(buildAutologinJs(user, pass), null)
    }

    private fun buildAutologinJs(username: String, password: String): String {
        val userJs = JSONObject.quote(username)
        val passJs = JSONObject.quote(password)
        return """
            (function() {
              if (window.__creabox_apptecnico_done) return;
              var USER = $userJs;
              var PASS = $passJs;

              function report(status) {
                try { CreaboxAutologin.onStatus(status); } catch (e) {}
              }

              function setVal(el, v) {
                if (!el || el.value === v) return;
                try {
                  var desc = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
                  if (desc && desc.set) desc.set.call(el, v);
                  else el.value = v;
                } catch (e) { el.value = v; }
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
                el.dispatchEvent(new Event('keyup', { bubbles: true }));
              }

              function findInput(name) {
                var ion = document.querySelector('ion-input[formcontrolname="' + name + '"]') ||
                          document.querySelector('ion-input[name="' + name + '"]');
                if (ion) {
                  if (ion.shadowRoot) {
                    var inner = ion.shadowRoot.querySelector('input,textarea');
                    if (inner) return inner;
                  }
                  var nested = ion.querySelector('input,textarea');
                  if (nested) return nested;
                }
                return document.querySelector('input[name="' + name + '"]') ||
                       document.querySelector('input[formcontrolname="' + name + '"]');
              }

              function loginFormVisible() {
                return !!(findInput('username') && findInput('password'));
              }

              function detectLoginError() {
                var body = (document.body && document.body.innerText || '').toLowerCase();
                var patterns = [
                  'incorrect', 'inválid', 'invalid', 'no es válid', 'no es valid',
                  'usuario o contraseña', 'usuario o contrase', 'credencial',
                  'autenticación fall', 'autenticacion fall', 'login failed',
                  'error al ingresar', 'error de acceso', 'datos incorrectos'
                ];
                for (var i = 0; i < patterns.length; i++) {
                  if (body.indexOf(patterns[i]) >= 0) return true;
                }
                var alerts = document.querySelectorAll('ion-toast, ion-alert, .toast, .alert');
                for (var j = 0; j < alerts.length; j++) {
                  var txt = (alerts[j].innerText || alerts[j].textContent || '').toLowerCase();
                  for (var k = 0; k < patterns.length; k++) {
                    if (txt.indexOf(patterns[k]) >= 0) return true;
                  }
                }
                return false;
              }

              if (!loginFormVisible()) {
                if (window.__creabox_apptecnico_login_clicked) {
                  window.__creabox_apptecnico_done = true;
                  report('success');
                }
                return;
              }

              if (window.__creabox_apptecnico_login_clicked) {
                var elapsed = Date.now() - (window.__creabox_apptecnico_click_time || 0);
                if (detectLoginError() && elapsed > 2500) {
                  window.__creabox_apptecnico_done = true;
                  report('credentials_error');
                  return;
                }
                if (elapsed > 12000) {
                  window.__creabox_apptecnico_done = true;
                  report('credentials_error');
                  return;
                }
                return;
              }

              var userInp = findInput('username');
              var passInp = findInput('password');
              setVal(userInp, USER);
              setVal(passInp, PASS);

              function clickIngresar() {
                var btn = document.querySelector('ion-button.button-vtr[type="submit"]') ||
                          document.querySelector('ion-button[type="submit"]');
                if (btn) {
                  var innerBtn = (btn.shadowRoot && btn.shadowRoot.querySelector('button')) || btn;
                  if (innerBtn && !innerBtn.disabled) {
                    innerBtn.click();
                    window.__creabox_apptecnico_login_clicked = true;
                    window.__creabox_apptecnico_click_time = Date.now();
                    console.log('[creabox] App Técnico: click Ingresar');
                    return true;
                  }
                }
                var form = document.querySelector('form');
                if (form) {
                  try {
                    if (typeof form.requestSubmit === 'function') {
                      form.requestSubmit();
                      window.__creabox_apptecnico_login_clicked = true;
                      window.__creabox_apptecnico_click_time = Date.now();
                      console.log('[creabox] App Técnico: form.requestSubmit');
                      return true;
                    }
                  } catch (e) {}
                }
                return false;
              }

              setTimeout(clickIngresar, 450);
            })();
        """.trimIndent()
    }

    private fun handleCordovaMessage(
        view: WebView?,
        cordovaMsg: String,
        result: JsPromptResult,
    ): Boolean {
        when {
            cordovaMsg.startsWith("gap_init:") -> {
                result.confirm(bridgeSecret.toString())
                return true
            }
            cordovaMsg.startsWith("gap_bridge_mode:") || cordovaMsg.startsWith("gap_poll:") -> {
                result.confirm("")
                return true
            }
            cordovaMsg.startsWith("gap:") -> {
                try {
                    val payload = JSONArray(cordovaMsg.substring(4))
                    val service = payload.optString(1)
                    val action = payload.optString(2)
                    val callbackId = payload.optString(3)

                    Log.d(TAG, "Cordova exec: $service.$action cb=$callbackId")

                    if (service == "Device" && action == "getDeviceInfo") {
                        deliverDeviceInfo(view, callbackId)
                        result.confirm("")
                        return true
                    }

                    if (callbackId.isNotBlank()) {
                        ackCordovaCallback(view, callbackId, JSONObject())
                    }
                    result.confirm("")
                    return true
                } catch (e: Exception) {
                    Log.w(TAG, "Cordova prompt error: ${e.message}")
                    result.confirm("")
                    return true
                }
            }
        }
        return false
    }

    private inner class CordovaNativeBridge {
        @JavascriptInterface
        fun exec(
            secret: Int,
            service: String,
            action: String,
            callbackId: String,
            args: String,
        ): String {
            if (secret != bridgeSecret) return ""
            Log.d(TAG, "Native exec: $service.$action cb=$callbackId args=$args")
            if (service == "Device" && action == "getDeviceInfo") {
                mainHandler.post { deliverDeviceInfo(webView, callbackId) }
            } else if (callbackId.isNotBlank()) {
                mainHandler.post { ackCordovaCallback(webView, callbackId, JSONObject()) }
            }
            return ""
        }

        @JavascriptInterface
        fun setNativeToJsBridgeMode(secret: Int, mode: Int) {}

        @JavascriptInterface
        fun retrieveJsMessages(secret: Int, fromOnlineEvent: Boolean): String = ""
    }

    private fun deliverDeviceInfo(view: WebView?, callbackId: String) {
        if (view == null || callbackId.isBlank()) return
        val deviceJson = buildDeviceJson().toString()
        val js =
            "try { cordova.callbackSuccess('$callbackId', " +
                "{status: cordova.callbackStatus.OK, message: $deviceJson, keepCallback: false}" +
                "); } catch(e) { console.log('device cb err', e); }"
        view.evaluateJavascript(js, null)
        view.evaluateJavascript(
            "try { window.__creaboxApplyDevice && window.__creaboxApplyDevice($deviceJson); } catch(e) {}",
            null,
        )
    }

    private fun ackCordovaCallback(view: WebView?, callbackId: String, payload: JSONObject) {
        if (view == null || callbackId.isBlank()) return
        val js =
            "try { cordova.callbackSuccess('$callbackId', " +
                "{status: cordova.callbackStatus.OK, message: $payload, keepCallback: false}" +
                "); } catch(e) {}"
        view.evaluateJavascript(js, null)
    }

    private fun buildDeviceJson(): JSONObject {
        val androidId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
            ?: "creabox-${Build.MODEL}".hashCode().toString()
        return JSONObject().apply {
            put("platform", "Android")
            put("version", Build.VERSION.RELEASE ?: "13")
            put("uuid", androidId)
            put("model", Build.MODEL ?: "Android")
            put("manufacturer", Build.MANUFACTURER ?: "unknown")
            put("isVirtual", false)
            put("serial", "unknown")
        }
    }

    private fun injectCordovaBootstrap(view: WebView?) {
        if (view == null) return
        val deviceJson = buildDeviceJson().toString()
        view.evaluateJavascript(buildBootstrapJs(deviceJson), null)
    }

    private fun buildBootstrapJs(deviceJson: String): String = """
        (function() {
          var info = $deviceJson;
          try {
            if (window.__creaboxApplyDevice) window.__creaboxApplyDevice(info);
          } catch (e) {}
          function patchDevice() {
            try {
              if (!window.device) return;
              window.device.available = true;
              window.device.platform = info.platform;
              window.device.version = info.version;
              window.device.uuid = info.uuid;
              window.device.model = info.model;
              window.device.manufacturer = info.manufacturer;
              window.device.isVirtual = info.isVirtual;
              window.device.serial = info.serial;
              window.device.cordova = (window.cordova && window.cordova.version) || '9.1.0';
            } catch (err) { console.log('patchDevice', err); }
          }
          function fireDeviceready() {
            try {
              if (window.cordova && typeof cordova.fireDocumentEvent === 'function') {
                cordova.fireDocumentEvent('deviceready');
              } else {
                var e = document.createEvent('Event');
                e.initEvent('deviceready', true, false);
                document.dispatchEvent(e);
              }
            } catch (err) {}
          }
          patchDevice();
          fireDeviceready();
        })();
    """.trimIndent()

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (::webView.isInitialized && webView.canGoBack()) {
            webView.goBack()
        } else {
            super.onBackPressed()
        }
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(autologinRunnable)
        autoUsername = null
        autoPassword = null
        if (::webView.isInitialized) {
            webView.stopLoading()
            webView.destroy()
        }
        super.onDestroy()
    }

    companion object {
        const val EXTRA_URL = "URL"
        const val EXTRA_AUTO_USERNAME = "AUTO_USERNAME"
        const val EXTRA_AUTO_PASSWORD = "AUTO_PASSWORD"
        const val RESULT_CREDENTIALS_ERROR = 1001
        private const val TAG = "AppTecnicoActivity"
    }
}
