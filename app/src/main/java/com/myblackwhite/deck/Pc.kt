package com.myblackwhite.deck

import android.graphics.BitmapFactory
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/** Un bouton du Deck, tel que decrit par le serveur PC. */
data class Bouton(
    val id: String,
    val nom: String,
    val type: String,
    val groupe: String,
    val couleur: Long?,
    val icone: ImageBitmap?,
)

/** Un profil Chrome du PC. */
data class ProfilChrome(val dossier: String, val nom: String, val compte: String, val photo: ImageBitmap?)

/** Une app du PC qu'on peut ajouter. bouton = id du bouton si elle est deja sur le Deck. */
data class AppPc(val cle: String, val nom: String, val bouton: String?)

data class BarreDetail(val nom: String, val part: Float, val texte: String)

data class Details(val lignes: List<Pair<String, String>>, val titreBarres: String, val barres: List<BarreDetail>)

data class Deck(val version: String, val colonnes: Int, val groupes: List<String>, val boutons: List<Bouton>)

/** Mesures du PC. ram/vram en Go, reseau en Ko/s. fps = 0 hors jeu. */
data class Perfs(
    val cpu: Float,
    val gpu: Float,
    val ram: Float,
    val ramTotal: Float,
    val vram: Float,
    val vramTotal: Float,
    val netIn: Float,
    val netOut: Float,
    val fps: Int,
    val jeu: String?,
    val cpuTemp: Float?,
    val gpuTemp: Float?,
    /** Temps de reponse d'internet en ms, null si inconnu ou pas de reponse. */
    val ping: Int?,
    /** Boutons dont l'app est ouverte sur le PC. */
    val actifs: Set<String> = emptySet(),
)

/**
 * Dialogue avec le serveur PC. Le cable USB + "adb reverse" fait que
 * localhost:8765 sur le telephone arrive sur le PC.
 */
object Pc {
    private const val BASE = "http://localhost:8765"
    private val cacheIcones = HashMap<String, ImageBitmap?>()

    private fun ouvrir(chemin: String, methode: String = "GET"): HttpURLConnection =
        (URL(BASE + chemin).openConnection() as HttpURLConnection).apply {
            requestMethod = methode
            connectTimeout = 1500
            readTimeout = 4000
            // Pas de connexion gardee ouverte : apres un debranchement, la suivante repart a neuf.
            setRequestProperty("Connection", "close")
            useCaches = false
        }

    /** Renvoie la version de la config du PC, ou null si le PC ne repond pas. */
    fun ping(): String? = runCatching {
        val c = ouvrir("/ping")
        try {
            if (c.responseCode == 200) c.inputStream.bufferedReader().readText() else null
        } finally {
            c.disconnect()
        }
    }.getOrNull()

    fun charger(viderIcones: Boolean): Deck {
        if (viderIcones) cacheIcones.clear()
        val c = ouvrir("/boutons")
        val texte = try {
            c.inputStream.bufferedReader(Charsets.UTF_8).readText()
        } finally {
            c.disconnect()
        }
        val json = JSONObject(texte)
        val liste = json.getJSONArray("boutons")
        val boutons = (0 until liste.length()).map { i ->
            val b = liste.getJSONObject(i)
            val id = b.getString("id")
            val icone = if (b.optBoolean("icone")) {
                cacheIcones.getOrPut(id) { telechargerIcone(id) }
            } else null
            val groupe = if (b.isNull("groupe")) "" else b.optString("groupe")
            Bouton(id, b.optString("nom"), b.optString("type", "app"), groupe, couleur(b.optString("couleur")), icone)
        }
        // Ordre des categories : celui du PC, puis celles qui n'y sont pas.
        val ordre = json.optJSONArray("groupes")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList()
        val groupes = (ordre + boutons.map { it.groupe }).filter { it.isNotBlank() }.distinct()
            .filter { g -> boutons.any { it.groupe == g } }
        return Deck(json.optString("version"), json.optInt("colonnes", 7).coerceIn(2, 12), groupes, boutons)
    }

    private fun telechargerIcone(id: String): ImageBitmap? = runCatching {
        val c = ouvrir("/icone/$id")
        try {
            BitmapFactory.decodeStream(c.inputStream)?.asImageBitmap()
        } finally {
            c.disconnect()
        }
    }.getOrNull()

    fun perfs(): Perfs? = runCatching {
        val c = ouvrir("/perfs")
        val texte = try {
            c.inputStream.bufferedReader(Charsets.UTF_8).readText()
        } finally {
            c.disconnect()
        }
        val j = JSONObject(texte)
        if (!j.has("cpu")) return@runCatching null
        val jeu = if (j.isNull("jeu")) null else j.optString("jeu").takeIf { it.isNotBlank() }
        Perfs(
            cpu = j.optDouble("cpu", 0.0).toFloat(),
            gpu = j.optDouble("gpu", 0.0).toFloat(),
            ram = j.optDouble("ram", 0.0).toFloat(),
            ramTotal = j.optDouble("ramTotal", 1.0).toFloat(),
            vram = j.optDouble("vram", 0.0).toFloat(),
            vramTotal = j.optDouble("vramTotal", 1.0).toFloat(),
            netIn = j.optDouble("netIn", 0.0).toFloat(),
            netOut = j.optDouble("netOut", 0.0).toFloat(),
            fps = j.optInt("fps", 0),
            jeu = jeu,
            cpuTemp = if (j.isNull("cpuTemp")) null else j.optDouble("cpuTemp").toFloat(),
            gpuTemp = if (j.isNull("gpuTemp")) null else j.optDouble("gpuTemp").toFloat(),
            ping = if (j.isNull("ping")) null else j.optInt("ping", -1).takeIf { it >= 0 },
            actifs = j.optJSONArray("actifs")?.let { a -> (0 until a.length()).map { a.optString(it) }.toSet() } ?: emptySet(),
        )
    }.getOrNull()

    private val cachePhotos = HashMap<String, ImageBitmap?>()

    fun profilsChrome(): List<ProfilChrome>? = runCatching {
        val c = ouvrir("/chrome/profils")
        val texte = try {
            c.inputStream.bufferedReader(Charsets.UTF_8).readText()
        } finally {
            c.disconnect()
        }
        val liste = org.json.JSONArray(texte)
        (0 until liste.length()).map { i ->
            val p = liste.getJSONObject(i)
            val dossier = p.getString("dossier")
            val photo = if (p.optBoolean("photo")) {
                cachePhotos.getOrPut(dossier) { image("/chrome/photo/" + encoder(dossier)) }
            } else null
            ProfilChrome(dossier, p.optString("nom"), p.optString("compte"), photo)
        }
    }.getOrNull()

    fun ouvrirChrome(dossier: String): Boolean = runCatching {
        val c = ouvrir("/chrome/ouvrir/" + encoder(dossier), "POST")
        try {
            c.doOutput = true
            c.outputStream.close()
            c.responseCode == 200
        } finally {
            c.disconnect()
        }
    }.getOrDefault(false)

    private fun encoder(s: String) = java.net.URLEncoder.encode(s, "UTF-8").replace("+", "%20")

    private fun image(chemin: String): ImageBitmap? = runCatching {
        val c = ouvrir(chemin)
        try {
            BitmapFactory.decodeStream(c.inputStream)?.asImageBitmap()
        } finally {
            c.disconnect()
        }
    }.getOrNull()

    /** Envoie l'appui au PC. Renvoie false si le PC ne repond pas. */
    fun appui(id: String): Boolean = runCatching {
        val c = ouvrir("/appui/$id", "POST")
        try {
            c.doOutput = true
            c.outputStream.close()
            c.responseCode == 200
        } finally {
            c.disconnect()
        }
    }.getOrDefault(false)

    // ---------- Apps du PC (ajout manuel) ----------

    private val cacheApps = HashMap<String, ImageBitmap?>()

    fun apps(): List<AppPc>? = runCatching {
        val liste = org.json.JSONArray(texte("/apps"))
        (0 until liste.length()).map { i ->
            val a = liste.getJSONObject(i)
            AppPc(a.getString("cle"), a.optString("nom"), if (a.isNull("bouton")) null else a.optString("bouton"))
        }
    }.getOrNull()

    fun iconeApp(cle: String): ImageBitmap? = synchronized(cacheApps) { cacheApps[cle] }
        ?: image("/apps/icone/$cle").also { synchronized(cacheApps) { cacheApps[cle] = it } }

    /** Ajoute l'app au Deck ; renvoie l'id du nouveau bouton. */
    fun ajouter(cle: String, groupe: String): String? = runCatching {
        val c = ouvrir("/ajouter/$cle?groupe=" + encoder(groupe), "POST")
        try {
            c.doOutput = true
            c.outputStream.close()
            if (c.responseCode == 200) c.inputStream.bufferedReader().readText().trim() else null
        } finally {
            c.disconnect()
        }
    }.getOrNull()

    /** Nouvel ordre des boutons d'une categorie. */
    fun ordre(ids: List<String>): Boolean = runCatching {
        val c = ouvrir("/ordre?ids=" + encoder(ids.joinToString(",")), "POST")
        try {
            c.doOutput = true
            c.outputStream.close()
            c.responseCode == 200
        } finally {
            c.disconnect()
        }
    }.getOrDefault(false)

    fun retirer(id: String): Boolean = runCatching {
        val c = ouvrir("/retirer/$id", "POST")
        try {
            c.doOutput = true
            c.outputStream.close()
            c.responseCode == 200
        } finally {
            c.disconnect()
        }
    }.getOrDefault(false)

    // ---------- Details d'une mesure ----------

    fun details(cle: String): Details? = runCatching {
        val j = JSONObject(texte("/details/$cle"))
        val l = j.optJSONArray("lignes") ?: org.json.JSONArray()
        val b = j.optJSONArray("barres") ?: org.json.JSONArray()
        Details(
            lignes = (0 until l.length()).map { l.getJSONObject(it).let { o -> o.optString("nom") to o.optString("valeur") } },
            titreBarres = j.optString("titreBarres"),
            barres = (0 until b.length()).map {
                b.getJSONObject(it).let { o -> BarreDetail(o.optString("nom"), o.optDouble("part", 0.0).toFloat(), o.optString("texte")) }
            },
        )
    }.getOrNull()

    /** Tous les composants du PC : (titre de la section, lignes nom -> valeur). */
    fun composants(dossier: java.io.File): List<Pair<String, List<Pair<String, String>>>>? = runCatching {
        val brut = texte("/composants")
        val liste = lireComposants(brut)
        // Garde une copie sur le telephone : on les revoit meme sans le PC.
        java.io.File(dossier, "composants.json").writeText(brut)
        liste
    }.getOrNull()

    /** Les composants enregistres sur le telephone lors de la derniere lecture. */
    fun composantsEnregistres(dossier: java.io.File): List<Pair<String, List<Pair<String, String>>>>? = runCatching {
        lireComposants(java.io.File(dossier, "composants.json").readText())
    }.getOrNull()

    private fun lireComposants(brut: String): List<Pair<String, List<Pair<String, String>>>> {
        val s = JSONObject(brut).getJSONArray("sections")
        return (0 until s.length()).map { i ->
            val o = s.getJSONObject(i)
            val l = o.optJSONArray("lignes") ?: org.json.JSONArray()
            o.optString("titre") to (0 until l.length()).map { l.getJSONObject(it).let { x -> x.optString("nom") to x.optString("valeur") } }
        }
    }

    private fun texte(chemin: String): String {
        val c = ouvrir(chemin)
        try {
            return c.inputStream.bufferedReader(Charsets.UTF_8).readText()
        } finally {
            c.disconnect()
        }
    }

    /** "#RRGGBB" -> couleur ARGB, ou null. */
    private fun couleur(texte: String?): Long? {
        if (texte.isNullOrBlank() || texte == "null") return null
        val hex = texte.removePrefix("#")
        if (hex.length != 6) return null
        return hex.toLongOrNull(16)?.let { 0xFF000000 or it }
    }
}
