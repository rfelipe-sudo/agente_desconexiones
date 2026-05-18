package com.karimpichara.turingandroid

import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TableLayout
import android.widget.TableRow
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.creacionestecnologicas.agente_desconexiones.R
import okhttp3.Call
import okhttp3.Credentials
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class CtoResultsActivity : AppCompatActivity() {

    private lateinit var imageCard: View
    private lateinit var portsCard: View
    private lateinit var progressBar: ProgressBar
    private lateinit var peloImage: ImageView
    private lateinit var imageErrorText: TextView
    private lateinit var tableTitle: TextView
    private lateinit var portTable: TableLayout
    private lateinit var tableErrorText: TextView
    private lateinit var refreshButton: Button
    private lateinit var lastUpdatedText: TextView
    private lateinit var reescanearButton: Button
    private lateinit var volverInicioButton: Button

    private val client = OkHttpClient.Builder()
        .connectTimeout(45, java.util.concurrent.TimeUnit.SECONDS)
        .readTimeout(45, java.util.concurrent.TimeUnit.SECONDS)
        .writeTimeout(45, java.util.concurrent.TimeUnit.SECONDS)
        .build()
    private val executor: ExecutorService = Executors.newFixedThreadPool(2)
    private val activeCalls = mutableListOf<Call>()

    private var boxType: String = ""
    private var rut: String = ""
    private var accessId: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_cto_results)

        imageCard       = findViewById(R.id.imageCard)
        portsCard       = findViewById(R.id.portsCard)
        progressBar     = findViewById(R.id.progressBar)
        peloImage       = findViewById(R.id.peloImage)
        imageErrorText  = findViewById(R.id.imageErrorText)
        tableTitle      = findViewById(R.id.tableTitle)
        portTable       = findViewById(R.id.portTable)
        tableErrorText  = findViewById(R.id.tableErrorText)
        refreshButton   = findViewById(R.id.refreshButton)
        lastUpdatedText = findViewById(R.id.lastUpdatedText)
        reescanearButton    = findViewById(R.id.reescanearButton)
        volverInicioButton  = findViewById(R.id.volverInicioButton)

        boxType = intent.getStringExtra("BOX_TYPE") ?: ""
        rut     = intent.getStringExtra("RUT") ?: ""

        reescanearButton.setOnClickListener { finish() }

        volverInicioButton.setOnClickListener {
            val intent = Intent(
                this,
                com.creacionestecnologicas.agente_desconexiones.MainActivity::class.java
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            intent.putExtra("CTO_CANCELLED", true)
            startActivity(intent)
        }

        refreshButton.setOnClickListener {
            val id = accessId
            if (id != null) {
                refreshButton.isEnabled = false
                refreshButton.text = "Refrescando estado..."
                fetchNyquistPorts(id)
            }
        }

        val formattedRut = formatRut(rut)
        fetchPeloImage(formattedRut)
        fetchPortData(formattedRut)
    }

    private fun fetchPeloImage(formattedRut: String) {
        val url = "https://turing.sbip.cl/api/pelo-image-v2?box_type=$boxType&rut=$formattedRut"
        val call = client.newCall(Request.Builder().url(url).build())
        synchronized(activeCalls) { activeCalls.add(call) }
        executor.execute {
            try {
                val response = call.execute()
                val bytes = response.body?.bytes()
                if (bytes != null && bytes.isNotEmpty()) {
                    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    if (bitmap != null) {
                        runOnUiThreadSafe {
                            progressBar.visibility = View.GONE
                            peloImage.setImageBitmap(bitmap)
                            peloImage.visibility = View.VISIBLE
                        }
                    } else {
                        val bodyPreview = String(bytes, 0, minOf(200, bytes.size))
                        runOnUiThreadSafe {
                            progressBar.visibility = View.GONE
                            imageErrorText.text = "No es imagen (code=${response.code}): $bodyPreview"
                            imageErrorText.visibility = View.VISIBLE
                        }
                    }
                } else {
                    runOnUiThreadSafe {
                        progressBar.visibility = View.GONE
                        imageErrorText.text = "Respuesta vacía (code=${response.code})"
                        imageErrorText.visibility = View.VISIBLE
                    }
                }
            } catch (_: Exception) {
                runOnUiThreadSafe {
                    progressBar.visibility = View.GONE
                    imageErrorText.text = "Error de conexión"
                    imageErrorText.visibility = View.VISIBLE
                }
            } finally {
                synchronized(activeCalls) { activeCalls.remove(call) }
            }
        }
    }

    private fun fetchPortData(formattedRut: String) {
        val url = "https://keplerv2.sbip.cl/api/v1/toa/get_pelo_db/$formattedRut"
        val call = client.newCall(Request.Builder().url(url).build())
        synchronized(activeCalls) { activeCalls.add(call) }
        executor.execute {
            try {
                val response = call.execute()
                val body = response.body?.string()
                if (body != null && response.isSuccessful) {
                    val json = JSONObject(body)
                    val data = json.optJSONObject("data")
                    accessId = data?.optString("access_id", "")
                    val niveles = data?.optJSONObject("niveles_final")
                    if (niveles != null) {
                        runOnUiThreadSafe {
                            portsCard.visibility = View.VISIBLE
                            tableTitle.visibility = View.VISIBLE
                            populatePortTable(niveles)
                            refreshButton.visibility = View.VISIBLE
                        }
                    } else {
                        runOnUiThreadSafe {
                            portsCard.visibility = View.VISIBLE
                            tableTitle.visibility = View.VISIBLE
                            tableErrorText.text = "No se encontraron datos de puertos"
                            tableErrorText.visibility = View.VISIBLE
                        }
                    }
                } else {
                    runOnUiThreadSafe {
                        tableTitle.visibility = View.VISIBLE
                        tableErrorText.text = "Error Kepler (code=${response.code})"
                        tableErrorText.visibility = View.VISIBLE
                    }
                }
            } catch (_: Exception) {
                runOnUiThreadSafe {
                    tableTitle.visibility = View.VISIBLE
                    tableErrorText.text = "Error Kepler"
                    tableErrorText.visibility = View.VISIBLE
                }
            } finally {
                synchronized(activeCalls) { activeCalls.remove(call) }
            }
        }
    }

    private fun fetchNyquistPorts(accessId: String) {
        // Si el accessId ya trae el prefijo "02-" (viene de Kepler), no lo duplicamos
        val fullAccessId = if (accessId.startsWith("02-")) accessId else "02-$accessId"
        // Mismo endpoint y credenciales que usa Flutter (nyquist_service.dart)
        val url = "https://nyquist.sbip.cl/onfide/estado-vecino/complete?access_id=$fullAccessId"
        val credential = Credentials.basic("0npVpRUG7MegtpmfdDuJ3A", "Ddw3u241Y0MN_x7ezZixKIJtk1ZRHpG6Zz2tCYrhXVg")
        android.util.Log.d("CtoResults", "Nyquist URL: $url")
        val call = client.newCall(
            Request.Builder()
                .url(url)
                .header("Authorization", credential)
                .header("Content-Type", "application/json")
                .build()
        )
        synchronized(activeCalls) { activeCalls.add(call) }
        executor.execute {
            try {
                val response = call.execute()
                val body = response.body?.string()
                android.util.Log.d("CtoResults", "Nyquist status=${response.code} body=${body?.take(300)}")
                if (body != null && response.isSuccessful) {
                    // La respuesta puede ser JSONObject o JSONArray (Flutter lo maneja igual)
                    val rootObj: JSONObject? = try { JSONObject(body) } catch (_: Exception) { null }
                    val rootArr = if (rootObj == null) {
                        try { org.json.JSONArray(body) } catch (_: Exception) { null }
                    } else null

                    // Normalizar: si es array tomamos el primer elemento
                    val json: JSONObject? = rootObj
                        ?: if (rootArr != null && rootArr.length() > 0) rootArr.optJSONObject(0) else null

                    if (json == null) {
                        runOnUiThreadSafe {
                            tableErrorText.text = "Nyquist: respuesta inesperada"
                            tableErrorText.visibility = View.VISIBLE
                            refreshButton.isEnabled = true
                            refreshButton.text = "Refrescar niveles"
                        }
                        return@execute
                    }

                    // Verificar success
                    if (json.has("success") && json.optBoolean("success") == false) {
                        val err = json.optString("error", "sin detalle")
                        runOnUiThreadSafe {
                            tableErrorText.text = "Nyquist: $err"
                            tableErrorText.visibility = View.VISIBLE
                            refreshButton.isEnabled = true
                            refreshButton.text = "Refrescar niveles"
                        }
                        return@execute
                    }

                    // Parsear array de puertos del formato /complete
                    val portsArray = json.optJSONArray("ports")
                    val now = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault()).format(Date())
                    runOnUiThreadSafe {
                        if (portsArray != null) {
                            populatePortTableFromComplete(portsArray)
                        } else {
                            // Fallback: formato plano u_cto_portN_rx_before (Kepler)
                            populatePortTable(json.optJSONObject("result") ?: json)
                        }
                        lastUpdatedText.text = "Última actualización: $now"
                        lastUpdatedText.visibility = View.VISIBLE
                        tableErrorText.visibility = View.GONE
                        refreshButton.isEnabled = true
                        refreshButton.text = "Refrescar niveles"
                    }
                } else {
                    runOnUiThreadSafe {
                        tableErrorText.text = "Nyquist error (code=${response.code})"
                        tableErrorText.visibility = View.VISIBLE
                        refreshButton.isEnabled = true
                        refreshButton.text = "Refrescar niveles"
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("CtoResults", "fetchNyquistPorts error", e)
                runOnUiThreadSafe {
                    tableErrorText.text = "Error Nyquist: ${e.message?.take(80)}"
                    tableErrorText.visibility = View.VISIBLE
                    refreshButton.isEnabled = true
                    refreshButton.text = "Refrescar niveles"
                }
            } finally {
                synchronized(activeCalls) { activeCalls.remove(call) }
            }
        }
    }

    // Parsea la respuesta de /complete: {"success":true,"ports":[{physical_port,rx_actual,rx_before,status},...]}
    private fun populatePortTableFromComplete(ports: org.json.JSONArray) {
        // Construir mapa por número de puerto físico
        data class PortData(val rxBefore: String, val rxActual: String, val status: String)
        val byPort = mutableMapOf<Int, PortData>()
        for (i in 0 until ports.length()) {
            val p = ports.optJSONObject(i) ?: continue
            val num = p.optInt("physical_port", -1)
            if (num < 1) continue
            byPort[num] = PortData(
                rxBefore = p.optString("rx_before", ""),
                rxActual = p.optString("rx_actual", ""),
                status   = p.optString("status", ""),
            )
        }

        portTable.removeAllViews()
        val headerRow = android.widget.TableRow(this).apply {
            setBackgroundColor(android.graphics.Color.parseColor("#F5F5F5"))
            setPadding(0, 0, 0, dpToPx(2))
        }
        for (col in listOf("Puerto", "rx_before", "rx_actual", "Estado")) {
            headerRow.addView(makeTextView(col, bold = true, isHeader = true))
        }
        portTable.addView(headerRow)

        for (portNum in 1..8) {
            val d = byPort[portNum] ?: continue
            val row = android.widget.TableRow(this).apply { setPadding(0, dpToPx(8), 0, dpToPx(8)) }
            row.addView(makeTextView("$portNum"))
            row.addView(makeTextView(displayValue(d.rxBefore)))
            row.addView(makeTextView(displayValue(d.rxActual), bold = true))
            row.addView(makeStatusBadge(d.status))
            portTable.addView(row)
        }
        portTable.visibility = View.VISIBLE
    }

    private fun populatePortTable(result: JSONObject) {
        portTable.removeAllViews()
        val headerRow = TableRow(this).apply {
            setBackgroundColor(Color.parseColor("#F5F5F5"))
            setPadding(0, 0, 0, dpToPx(2))
        }
        for (col in listOf("Puerto", "rx_before", "rx_actual", "Estado")) {
            headerRow.addView(makeTextView(col, bold = true, isHeader = true))
        }
        portTable.addView(headerRow)
        for (i in 1..8) {
            val rxBefore = result.optString("u_cto_port${i}_rx_before", "")
            val rxActual = result.optString("u_cto_port${i}_rx_actual", "")
            val status   = result.optString("u_cto_port${i}_status", "")
            if (rxBefore.isEmpty() && rxActual.isEmpty() && status.isEmpty()) continue
            val row = TableRow(this).apply { setPadding(0, dpToPx(8), 0, dpToPx(8)) }
            row.addView(makeTextView("$i"))
            row.addView(makeTextView(displayValue(rxBefore)))
            row.addView(makeTextView(displayValue(rxActual), bold = true))
            row.addView(makeStatusBadge(status))
            portTable.addView(row)
        }
        portTable.visibility = View.VISIBLE
    }

    private fun displayValue(value: String) = if (value.isEmpty() || value == "null") "—" else value

    private fun makeTextView(text: String, bold: Boolean = false, isHeader: Boolean = false) =
        TextView(this).apply {
            this.text = text
            setPadding(dpToPx(10), dpToPx(8), dpToPx(10), dpToPx(8))
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(if (isHeader) Color.parseColor("#666666") else Color.parseColor("#333333"))
            if (bold) setTypeface(typeface, Typeface.BOLD)
        }

    private fun makeStatusBadge(status: String): TextView {
        val bgColor = when (status) {
            "OK"    -> Color.parseColor("#4CAF50")
            "NO_OK" -> Color.parseColor("#F44336")
            "Error" -> Color.parseColor("#FF9800")
            else    -> Color.parseColor("#999999")
        }
        return TextView(this).apply {
            text = displayValue(status)
            setTextColor(Color.WHITE)
            setTypeface(typeface, Typeface.BOLD)
            textSize = 12f
            gravity = Gravity.CENTER
            setPadding(dpToPx(12), dpToPx(4), dpToPx(12), dpToPx(4))
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(bgColor)
                cornerRadius = dpToPx(12).toFloat()
            }
        }
    }

    private fun dpToPx(dp: Int) = (dp * resources.displayMetrics.density).toInt()

    private fun runOnUiThreadSafe(action: () -> Unit) {
        runOnUiThread { if (!isFinishing && !isDestroyed) action() }
    }

    override fun onDestroy() {
        super.onDestroy()
        synchronized(activeCalls) {
            activeCalls.forEach { it.cancel() }
            activeCalls.clear()
        }
        executor.shutdownNow()
    }
}
