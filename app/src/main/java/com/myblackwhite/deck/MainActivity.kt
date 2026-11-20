package com.myblackwhite.deck

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.view.HapticFeedbackConstants
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.compose.setContent
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.staggeredgrid.LazyVerticalStaggeredGrid
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridCells
import androidx.compose.foundation.lazy.staggeredgrid.items as itemsEchelonnes
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.animation.core.animateIntOffsetAsState
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.key
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.round
import androidx.compose.ui.zIndex
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

// ---------- Palette : noir profond, gris doux, couleur seulement pour les alertes ----------
private val Fond = Color(0xFF07080A)
private val Surface = Color(0xFF111215)
private val SurfaceHaute = Color(0xFF1A1B20)
private val Trait = Color(0xFF1E2025)
private val Texte = Color(0xFFF2F3F5)
private val Texte2 = Color(0xFF9DA1AA)
private val Texte3 = Color(0xFF5C6069)
private val Piste = Color(0xFF24262C)
private val Vert = Color(0xFF3DDC84)
private val Ambre = Color(0xFFFFB020)
private val Rouge = Color(0xFFFF5252)

private fun niveau(part: Float) = when {
    part >= 0.85f -> Rouge
    part >= 0.65f -> Ambre
    else -> Texte
}

/** FPS : vert si fluide, ambre si moyen, rouge si ca rame. */
private fun couleurFps(fps: Int) = when {
    fps >= 55 -> Vert
    fps >= 30 -> Ambre
    else -> Rouge
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        // C'est l'ecran d'accueil : le bouton Retour ne fait rien.
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {}
        })
        setContent { EcranDeck() }
    }

    override fun onResume() {
        super.onResume()
        WindowInsetsControllerCompat(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
    }
}

/** Les 60 dernieres secondes, pour les courbes. */
class Historique {
    val cpu = mutableStateListOf<Float>()
    val gpu = mutableStateListOf<Float>()
    val fps = mutableStateListOf<Float>()
    val ram = mutableStateListOf<Float>()
    val vram = mutableStateListOf<Float>()
    val net = mutableStateListOf<Float>()

    fun ajouter(p: Perfs) {
        pousser(cpu, p.cpu)
        pousser(gpu, p.gpu)
        pousser(fps, p.fps.toFloat())
        pousser(ram, p.ram / p.ramTotal * 100f)
        pousser(vram, p.vram / p.vramTotal * 100f)
        pousser(net, p.netIn)
    }

    fun courbe(cle: String): List<Float> = when (cle) {
        "cpu" -> cpu
        "gpu" -> gpu
        "ram" -> ram
        "vram" -> vram
        "reseau" -> net
        else -> fps
    }

    private fun pousser(l: SnapshotStateList<Float>, v: Float) {
        l.add(v)
        if (l.size > 60) l.removeAt(0)
    }
}

@Composable
fun EcranDeck() {
    val contexte = LocalContext.current
    val scope = rememberCoroutineScope()
    var deck by remember { mutableStateOf<Deck?>(null) }
    var connecte by remember { mutableStateOf(false) }
    var demandeRecharge by remember { mutableIntStateOf(0) }
    var menu by remember { mutableStateOf(false) }
    var perfs by remember { mutableStateOf<Perfs?>(null) }
    var page by rememberSaveable { mutableStateOf("touches") } // touches / chrome / ajout / perfs
    var mesure by rememberSaveable { mutableStateOf("cpu") } // case ouverte sur la page perfs
    var groupe by rememberSaveable { mutableStateOf("") }
    var profils by remember { mutableStateOf<List<ProfilChrome>?>(null) }
    var details by remember { mutableStateOf<Details?>(null) }
    var edition by remember { mutableStateOf(false) } // mode organisation des icones
    val histo = remember { Historique() }

    // Recharge les boutons tout de suite (apres un ajout ou un retrait), sans vider les icones.
    fun rafraichir() {
        scope.launch {
            withContext(Dispatchers.IO) { runCatching { Pc.charger(false) }.getOrNull() }?.let { deck = it }
        }
    }

    // Page de details : mise a jour toutes les 1,5 s tant qu'elle est ouverte.
    LaunchedEffect(page, mesure) {
        details = null
        if (page != "perfs" || mesure == "pc") return@LaunchedEffect
        val cle = mesure
        while (true) {
            withContext(Dispatchers.IO) { Pc.details(cle) }?.let { details = it }
            delay(1500)
        }
    }

    // Boutons : charge, puis verifie toutes les 3 s que le PC repond
    // et que sa config n'a pas change.
    LaunchedEffect(demandeRecharge) {
        var vider = demandeRecharge > 0
        while (true) {
            val version = withContext(Dispatchers.IO) { Pc.ping() }
            connecte = version != null
            if (version != null && (deck == null || deck?.version != version || vider)) {
                val nouveau = withContext(Dispatchers.IO) { runCatching { Pc.charger(vider) }.getOrNull() }
                if (nouveau != null) {
                    deck = nouveau
                    vider = false
                }
            }
            // Deconnecte : on reessaie tres souvent pour revenir des que le PC repond.
            delay(if (connecte) 3000 else 500)
        }
    }

    // Performances : affichage toutes les 0,5 s, courbes une fois par seconde.
    LaunchedEffect(Unit) {
        var tour = 0
        var echecs = 0
        while (true) {
            val p = withContext(Dispatchers.IO) { Pc.perfs() }
            perfs = p
            // Sert aussi a voir tout de suite si le PC s'en va ou revient.
            echecs = if (p != null || withContext(Dispatchers.IO) { Pc.ping() } != null) 0 else echecs + 1
            if (echecs >= 2) connecte = false
            if (p != null && tour++ % 2 == 0) histo.ajouter(p)
            delay(500)
        }
    }

    val d = deck
    val groupes = d?.groupes ?: emptyList()
    val groupeActif = groupe.takeIf { it in groupes } ?: groupes.firstOrNull() ?: ""
    LaunchedEffect(page, groupeActif) { edition = false }

    Box(Modifier.fillMaxSize().background(Fond)) {
        Row(Modifier.fillMaxSize().padding(12.dp)) {
            Rail(
                groupes = groupes,
                compte = { g -> d?.boutons?.count { it.groupe == g } ?: 0 },
                actif = if (page == "touches") groupeActif else null,
                onGroupe = { groupe = it; page = "touches" },
                onMenu = { menu = true },
                logoActif = page in listOf("perfs", "ajout", "composants"),
                // Logo : 1 appui = performances, 2 = composants du PC, 3 = ajouter des apps.
                onLogo = { appuis ->
                    val voulu = when {
                        appuis >= 3 -> "ajout"
                        appuis == 2 -> "composants"
                        else -> "perfs"
                    }
                    page = if (page == voulu || (appuis == 1 && page != "touches")) "touches" else voulu
                },
            )
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f).fillMaxHeight()) {
                // Le bandeau des mesures n'apparait que sur la page des performances.
                if (page == "perfs") {
                    BandeauPerfs(perfs, ouvert = mesure) { mesure = it }
                    Spacer(Modifier.height(12.dp))
                }
                Box(Modifier.weight(1f).fillMaxWidth()) {
                    AnimatedContent(
                        targetState = (if (page == "perfs") "perfs:$mesure" else page) to groupeActif,
                        transitionSpec = { fadeIn(tween(180)) togetherWith fadeOut(tween(120)) },
                        label = "page",
                    ) { (p, g) ->
                        when {
                            p == "composants" -> PageComposants()
                            p.startsWith("perfs:") -> PageDetail(p.removePrefix("perfs:"), perfs, histo, details)
                            p == "ajout" -> PageAjout(
                                groupes = groupes,
                                groupeDepart = groupeActif,
                                onChange = { rafraichir() },
                            )
                            p == "chrome" -> PageProfils(
                                profils,
                                onChoix = { profil ->
                                    page = "touches"
                                    scope.launch {
                                        val ok = withContext(Dispatchers.IO) { Pc.ouvrirChrome(profil.dossier) }
                                        if (!ok) connecte = false
                                    }
                                },
                                onRetour = { page = "touches" },
                            )
                            else -> {
                                val liste = d?.boutons?.filter { g.isBlank() || it.groupe == g } ?: emptyList()
                                if (liste.isNotEmpty()) {
                                    GrilleTouches(
                                        liste, connecte, edition, perfs?.actifs ?: emptySet(),
                                        onEdition = { edition = true },
                                        onOrdre = { ids -> scope.launch { withContext(Dispatchers.IO) { Pc.ordre(ids) } } },
                                    ) { b ->
                                        if (b.type == "chrome") {
                                            // Chrome : on choisit d'abord le profil sur le telephone.
                                            profils = null
                                            page = "chrome"
                                            scope.launch { profils = withContext(Dispatchers.IO) { Pc.profilsChrome() } }
                                        } else {
                                            scope.launch {
                                                val ok = withContext(Dispatchers.IO) { Pc.appui(b.id) }
                                                if (!ok) connecte = false
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Mode organisation : bandeau en bas avec le bouton Termine.
        if (edition && page == "touches") {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 14.dp)
                    .clip(CircleShape)
                    .background(SurfaceHaute)
                    .border(1.dp, Texte.copy(alpha = 0.3f), CircleShape)
                    .padding(start = 16.dp, end = 6.dp, top = 6.dp, bottom = 6.dp),
            ) {
                Text("Glisse les icones pour les ranger", color = Texte2, fontSize = 12.sp)
                Spacer(Modifier.width(12.dp))
                Text(
                    "Termine", color = Color.Black, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                    modifier = Modifier.clip(CircleShape).background(Texte).clickable { edition = false }
                        .padding(horizontal = 14.dp, vertical = 6.dp),
                )
            }
        }

        if (!connecte) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 18.dp)
                    .clip(CircleShape)
                    .background(SurfaceHaute)
                    .border(1.dp, Rouge.copy(alpha = 0.5f), CircleShape)
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            ) {
                Box(Modifier.size(7.dp).clip(CircleShape).background(Rouge))
                Spacer(Modifier.width(10.dp))
                Text(
                    if (d == null) "Branche le cable et lance le serveur Deck sur le PC" else "PC deconnecte, reconnexion...",
                    color = Texte,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                )
            }
        }
    }

    if (menu) {
        AlertDialog(
            onDismissRequest = { menu = false },
            containerColor = SurfaceHaute,
            titleContentColor = Texte,
            title = { Text("Deck") },
            text = {
                Column {
                    TextButton(onClick = { menu = false; demandeRecharge++ }) { Text("Recharger les boutons", color = Texte) }
                    TextButton(onClick = {
                        menu = false
                        contexte.startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }) { Text("Parametres du telephone", color = Texte) }
                    TextButton(onClick = {
                        menu = false
                        contexte.startActivity(Intent(Settings.ACTION_HOME_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }) { Text("Changer d'ecran d'accueil", color = Texte) }
                }
            },
            confirmButton = { TextButton(onClick = { menu = false }) { Text("Fermer", color = Texte2) } },
        )
    }
}

// ---------- Barre laterale : logo, categories, heure ----------

@Composable
fun Rail(
    groupes: List<String>,
    compte: (String) -> Int,
    actif: String?,
    onGroupe: (String) -> Unit,
    onMenu: () -> Unit,
    logoActif: Boolean,
    onLogo: (appuis: Int) -> Unit,
) {
    var heure by remember { mutableStateOf(Date()) }
    LaunchedEffect(Unit) {
        while (true) {
            heure = Date()
            delay(5000)
        }
    }
    // Compte les appuis rapproches sur le logo, puis decide 0,35 s apres le dernier.
    val scope = rememberCoroutineScope()
    val vue = LocalView.current
    var appuis by remember { mutableIntStateOf(0) }
    var attente by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.width(96.dp).fillMaxHeight(),
    ) {
        // Logo : 1 appui = performances, 3 appuis = ajouter des apps, appui long = menu.
        Logo(
            logoActif,
            Modifier
                .padding(top = 4.dp)
                .size(48.dp)
                .clip(RoundedCornerShape(14.dp))
                .combinedClickable(
                    onClick = {
                        vue.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                        appuis++
                        attente?.cancel()
                        attente = scope.launch {
                            delay(if (appuis >= 3) 0 else 350)
                            val n = appuis
                            appuis = 0
                            onLogo(n)
                        }
                    },
                    onLongClick = onMenu,
                ),
        )
        Spacer(Modifier.height(12.dp))
        Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.fillMaxWidth()) {
            groupes.forEach { g -> ItemRail(g, compte(g), g == actif) { onGroupe(g) } }
        }
        Spacer(Modifier.weight(1f))
        Text(SimpleDateFormat("HH:mm", Locale.FRANCE).format(heure), color = Texte, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        Text(
            SimpleDateFormat("EEE d MMM", Locale.FRANCE).format(heure),
            color = Texte3,
            fontSize = 10.sp,
            modifier = Modifier.padding(bottom = 4.dp),
        )
    }
}

@Composable
fun Logo(actif: Boolean, modifier: Modifier) {
    val fond by animateColorAsState(if (actif) Texte else Surface, label = "logo")
    val carre = if (actif) Color.Black else Texte
    Canvas(modifier.background(fond).border(1.dp, if (actif) Color.Transparent else Trait, RoundedCornerShape(14.dp))) {
        val c = size.width * 0.17f
        val e = size.width * 0.06f
        val x0 = (size.width - (3 * c + 2 * e)) / 2f
        val y0 = (size.height - (2 * c + e)) / 2f
        for (l in 0..1) for (k in 0..2) {
            drawRoundRect(
                carre,
                topLeft = Offset(x0 + k * (c + e), y0 + l * (c + e)),
                size = Size(c, c),
                cornerRadius = CornerRadius(c * 0.25f),
            )
        }
    }
}

@Composable
fun ItemRail(nom: String, nb: Int, actif: Boolean, onClick: () -> Unit) {
    val fond by animateColorAsState(if (actif) Texte else Color.Transparent, label = "fond")
    val encre by animateColorAsState(if (actif) Color.Black else Texte2, label = "encre")
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
        modifier = Modifier
            .fillMaxWidth()
            .height(42.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(fond)
            .clickable(onClick = onClick),
    ) {
        Text(nom, color = encre, fontSize = 13.sp, fontWeight = if (actif) FontWeight.Bold else FontWeight.Medium, maxLines = 1)
        Text("$nb", color = if (actif) Color(0xFF555555) else Texte3, fontSize = 10.sp)
    }
}

// ---------- Bandeau des performances (toujours visible) ----------

@Composable
fun BandeauPerfs(p: Perfs?, ouvert: String?, onStat: (String) -> Unit) {
    val forme = RoundedCornerShape(16.dp)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp)
            .clip(forme)
            .background(Surface)
            .border(1.dp, if (ouvert != null) Texte.copy(alpha = 0.35f) else Trait, forme)
            .padding(horizontal = 4.dp),
    ) {
        // Chaque case ouvre (ou referme) ses details.
        fun RowScopeM(cle: String, poids: Float) = Modifier
            .weight(poids)
            .fillMaxHeight()
            .padding(vertical = 5.dp)
            .clip(RoundedCornerShape(11.dp))
            .background(if (ouvert == cle) SurfaceHaute else Color.Transparent)
            .clickable { onStat(cle) }
        Stat("CPU", p?.let { "${it.cpu.roundToInt()}%" }, p?.cpuTemp, p?.cpu?.div(100f), RowScopeM("cpu", 1f))
        Separateur()
        Stat("GPU", p?.let { "${it.gpu.roundToInt()}%" }, p?.gpuTemp, p?.gpu?.div(100f), RowScopeM("gpu", 1f))
        Separateur()
        Stat("RAM", p?.let { "${un(it.ram)} Go" }, null, p?.let { it.ram / it.ramTotal }, RowScopeM("ram", 1f))
        Separateur()
        Stat("VRAM", p?.let { "${un(it.vram)} Go" }, null, p?.let { it.vram / it.vramTotal }, RowScopeM("vram", 1f))
        Separateur()
        Stat(
            "RESEAU", p?.let { "↓${debit(it.netIn)}" }, null, null, RowScopeM("reseau", 1.15f), sous = p?.let { "↑${debit(it.netOut)}" },
            badge = p?.ping?.let { "$it ms" to couleurPing(it) },
        )
        PastilleFps(
            p,
            ouvert == "fps",
            Modifier.weight(1.25f).fillMaxHeight().padding(vertical = 8.dp, horizontal = 4.dp).clickable { onStat("fps") },
        )
    }
}

@Composable
fun Separateur() {
    Box(Modifier.width(1.dp).height(26.dp).background(Trait))
}

@Composable
fun Stat(
    titre: String,
    valeur: String?,
    temp: Float?,
    part: Float?,
    modifier: Modifier,
    sous: String? = null,
    badge: Pair<String, Color>? = null,
) {
    Column(modifier.padding(horizontal = 10.dp), verticalArrangement = Arrangement.Center) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(titre, color = Texte3, fontSize = 8.sp, letterSpacing = 1.6.sp, fontWeight = FontWeight.Bold)
            if (badge != null) {
                Spacer(Modifier.width(6.dp))
                Text(badge.first, color = badge.second, fontSize = 9.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            }
        }
        Row(verticalAlignment = Alignment.Bottom) {
            Text(valeur ?: "--", color = Texte, fontSize = 15.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            if (temp != null) {
                Spacer(Modifier.width(5.dp))
                Text(
                    "${temp.roundToInt()}°",
                    color = couleurTemp(temp),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(bottom = 1.dp),
                )
            }
            if (sous != null) {
                Spacer(Modifier.width(6.dp))
                Text(sous, color = Texte2, fontSize = 11.sp, maxLines = 1, modifier = Modifier.padding(bottom = 1.dp))
            }
        }
        Spacer(Modifier.height(4.dp))
        if (part != null) Jauge(part) else Spacer(Modifier.height(2.dp))
    }
}

/** Ping : vert si rapide, ambre si moyen, rouge si lent. */
private fun couleurPing(ms: Int) = when {
    ms < 40 -> Vert
    ms < 90 -> Ambre
    else -> Rouge
}

/** Temperature : gris normal, ambre a 70 degres, rouge a 85. */
private fun couleurTemp(t: Float) = when {
    t >= 85f -> Rouge
    t >= 70f -> Ambre
    else -> Texte2
}

@Composable
fun Jauge(part: Float) {
    val anime by animateFloatAsState(part.coerceIn(0f, 1f), label = "jauge")
    Box(Modifier.fillMaxWidth().height(2.dp).clip(CircleShape).background(Piste)) {
        Box(Modifier.fillMaxWidth(anime).fillMaxHeight().clip(CircleShape).background(niveau(part)))
    }
}

@Composable
fun PastilleFps(p: Perfs?, ouvert: Boolean, modifier: Modifier) {
    val enJeu = p != null && p.fps > 0
    val couleur = if (enJeu) couleurFps(p!!.fps) else Texte3
    val forme = RoundedCornerShape(11.dp)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
        modifier = modifier
            .clip(forme)
            .background(if (enJeu) couleur.copy(alpha = if (ouvert) 0.22f else 0.10f) else SurfaceHaute)
            .border(1.dp, if (ouvert) Texte.copy(alpha = 0.6f) else if (enJeu) couleur.copy(alpha = 0.45f) else Trait, forme)
            .padding(horizontal = 10.dp),
    ) {
        Text(if (enJeu) "${p!!.fps}" else "--", color = couleur, fontSize = 21.sp, fontWeight = FontWeight.Black)
        Spacer(Modifier.width(7.dp))
        Column {
            Text("FPS", color = couleur, fontSize = 8.sp, letterSpacing = 1.4.sp, fontWeight = FontWeight.Bold)
            Text(
                if (enJeu) (p!!.jeu ?: "") else "hors jeu",
                color = Texte2,
                fontSize = 9.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

// ---------- Choix du profil Chrome ----------

@Composable
fun PageProfils(profils: List<ProfilChrome>?, onChoix: (ProfilChrome) -> Unit, onRetour: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        EnTete("Chrome", "Choisis un profil", onRetour)
        if (profils == null) {
            Text("Chargement...", color = Texte3, fontSize = 13.sp)
            return@Column
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.weight(1f).fillMaxWidth()) {
            profils.forEach { profil -> CarteProfil(profil, Modifier.weight(1f)) { onChoix(profil) } }
        }
    }
}

@Composable
fun EnTete(titre: String, sous: String, onRetour: (() -> Unit)? = null) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp)) {
        if (onRetour != null) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(32.dp)
                    .clip(CircleShape)
                    .background(SurfaceHaute)
                    .clickable(onClick = onRetour),
            ) { Text("←", color = Texte, fontSize = 15.sp, fontWeight = FontWeight.Bold) }
            Spacer(Modifier.width(12.dp))
        }
        Text(titre, color = Texte, fontSize = 17.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.width(10.dp))
        Text(sous, color = Texte3, fontSize = 12.sp)
    }
}

@Composable
fun CarteProfil(profil: ProfilChrome, modifier: Modifier, onClick: () -> Unit) {
    val vue = LocalView.current
    val interaction = remember { MutableInteractionSource() }
    val appuye by interaction.collectIsPressedAsState()
    val echelle by animateFloatAsState(if (appuye) 0.96f else 1f, label = "echelle")
    val forme = RoundedCornerShape(20.dp)
    BoxWithConstraints(modifier.fillMaxHeight()) {
        val photo = minOf(maxWidth * 0.6f, maxHeight * 0.48f)
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .scale(echelle)
                .fillMaxSize()
                .clip(forme)
                .background(if (appuye) SurfaceHaute else Surface)
                .border(1.dp, if (appuye) Texte.copy(alpha = 0.35f) else Trait, forme)
                .clickable(interactionSource = interaction, indication = null) {
                    vue.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                    onClick()
                }
                .padding(8.dp),
        ) {
            if (profil.photo != null) {
                Image(profil.photo, contentDescription = null, filterQuality = FilterQuality.High, modifier = Modifier.size(photo).clip(CircleShape))
            } else {
                Box(contentAlignment = Alignment.Center, modifier = Modifier.size(photo).clip(CircleShape).background(Piste)) {
                    Text(profil.nom.take(1).uppercase(), color = Texte, fontSize = (photo.value * 0.4f).sp, fontWeight = FontWeight.Bold)
                }
            }
            Spacer(Modifier.height(10.dp))
            Text(profil.nom, color = Texte, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (profil.compte.isNotBlank() && profil.compte != profil.nom) {
                Text(profil.compte, color = Texte3, fontSize = 10.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

// ---------- Page detaillee : courbes sur 60 s ----------

@Composable
fun PageDetail(cle: String, p: Perfs?, h: Historique, d: Details?) {
    val courbe = h.courbe(cle)
    val max = when (cle) {
        "fps" -> maxOf(60f, (courbe.maxOrNull() ?: 0f) * 1.2f)
        "reseau" -> maxOf(100f, (courbe.maxOrNull() ?: 0f) * 1.2f)
        else -> 100f
    }
    val (titre, valeur, unite) = when (cle) {
        "cpu" -> Triple("PROCESSEUR", p?.let { "${it.cpu.roundToInt()}" }, "%")
        "gpu" -> Triple("CARTE GRAPHIQUE", p?.let { "${it.gpu.roundToInt()}" }, "%")
        "ram" -> Triple("MEMOIRE VIVE", p?.let { un(it.ram) }, p?.let { "/ ${it.ramTotal.roundToInt()} Go" } ?: "Go")
        "vram" -> Triple("MEMOIRE VIDEO", p?.let { un(it.vram) }, p?.let { "/ ${it.vramTotal.roundToInt()} Go" } ?: "Go")
        "reseau" -> Triple("RESEAU (RECEPTION)", p?.let { debit(it.netIn) }, p?.let { "↑ ${debit(it.netOut)}" } ?: "")
        else -> Triple("IMAGES / S", p?.let { if (it.fps > 0) "${it.fps}" else "--" }, p?.jeu ?: "hors jeu")
    }
    val temp = when (cle) {
        "cpu" -> p?.cpuTemp
        "gpu" -> p?.gpuTemp
        else -> null
    }
    // FPS : moyenne, minimum et maximum sur la minute, calcules ici.
    val lignes = buildList {
        addAll(d?.lignes ?: emptyList())
        if (cle == "fps") {
            val enJeu = h.fps.filter { it > 0f }
            if (enJeu.isNotEmpty()) {
                add("Moyenne (1 min)" to "${enJeu.average().roundToInt()}")
                add("Minimum (1 min)" to "${enJeu.min().roundToInt()}")
                add("Maximum (1 min)" to "${enJeu.max().roundToInt()}")
            }
        }
    }
    val forme = RoundedCornerShape(20.dp)
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxSize()) {
        CartePerf(
            titre, valeur, unite, temp, courbe, max, Modifier.weight(1.1f),
            couleurForcee = if (cle == "fps") p?.takeIf { it.fps > 0 }?.let { couleurFps(it.fps) } else null,
        )
        // Infos
        Column(
            Modifier.weight(1f).fillMaxHeight().clip(forme).background(Surface).border(1.dp, Trait, forme)
                .padding(horizontal = 14.dp, vertical = 12.dp),
        ) {
            Text("INFOS", color = Texte3, fontSize = 9.sp, letterSpacing = 1.6.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(6.dp))
            if (lignes.isEmpty()) Text("Chargement...", color = Texte3, fontSize = 12.sp)
            Column(verticalArrangement = Arrangement.SpaceEvenly, modifier = Modifier.weight(1f, fill = false)) {
                lignes.take(10).forEach { (nom, v) ->
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
                        Text(nom, color = Texte2, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                        Spacer(Modifier.width(8.dp))
                        Text(v, color = Texte, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
        // Barres : coeurs du processeur, moteurs de la carte, programmes...
        if (d != null && d.barres.isNotEmpty()) {
            Column(
                Modifier.weight(1f).fillMaxHeight().clip(forme).background(Surface).border(1.dp, Trait, forme)
                    .padding(horizontal = 14.dp, vertical = 12.dp),
            ) {
                Text(d.titreBarres.uppercase(), color = Texte3, fontSize = 9.sp, letterSpacing = 1.6.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                if (d.barres.size > 8) BarresVerticales(d.barres, Modifier.weight(1f).fillMaxWidth())
                else Column(verticalArrangement = Arrangement.SpaceEvenly, modifier = Modifier.weight(1f)) {
                    d.barres.forEach { b -> LigneBarre(b) }
                }
            }
        }
    }
}

@Composable
fun LigneBarre(b: BarreDetail) {
    Column(Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(b.nom, color = Texte2, fontSize = 10.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            Text(b.texte, color = Texte, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
        }
        Spacer(Modifier.height(3.dp))
        val anime by animateFloatAsState(b.part.coerceIn(0f, 1f), label = "barre")
        Box(Modifier.fillMaxWidth().height(4.dp).clip(CircleShape).background(Piste)) {
            Box(Modifier.fillMaxWidth(anime).fillMaxHeight().clip(CircleShape).background(niveau(b.part)))
        }
    }
}

/** Beaucoup de barres (coeurs du processeur) : colonnes cote a cote. */
@Composable
fun BarresVerticales(barres: List<BarreDetail>, modifier: Modifier) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), modifier = modifier) {
        barres.forEach { b ->
            val anime by animateFloatAsState(b.part.coerceIn(0f, 1f), label = "coeur")
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.weight(1f).fillMaxHeight()) {
                Box(
                    contentAlignment = Alignment.BottomCenter,
                    modifier = Modifier.weight(1f).fillMaxWidth().clip(RoundedCornerShape(4.dp)).background(Piste),
                ) {
                    Box(Modifier.fillMaxWidth().fillMaxHeight(anime).background(niveau(b.part)))
                }
                Spacer(Modifier.height(3.dp))
                Text(b.nom, color = Texte3, fontSize = 8.sp, maxLines = 1)
            }
        }
    }
}

// ---------- Ajout d'apps du PC ----------

@Composable
fun PageAjout(groupes: List<String>, groupeDepart: String, onChange: () -> Unit) {
    val scope = rememberCoroutineScope()
    var apps by remember { mutableStateOf<List<AppPc>?>(null) }
    var erreur by remember { mutableStateOf(false) }
    var cible by remember { mutableStateOf(groupeDepart) }
    LaunchedEffect(Unit) {
        val l = withContext(Dispatchers.IO) { Pc.apps() }
        if (l == null) erreur = true else apps = l
    }
    Column(Modifier.fillMaxSize()) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp)) {
            Column {
                Text("Apps du PC", color = Texte, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                Text("Appuie pour ajouter, encore pour retirer", color = Texte3, fontSize = 9.sp)
            }
            Spacer(Modifier.width(12.dp))
            Text("Ajouter dans :", color = Texte3, fontSize = 11.sp)
            Spacer(Modifier.width(8.dp))
            groupes.forEach { g ->
                val actif = g == cible
                Text(
                    g,
                    color = if (actif) Color.Black else Texte2,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .padding(end = 6.dp)
                        .clip(CircleShape)
                        .background(if (actif) Texte else SurfaceHaute)
                        .clickable { cible = g }
                        .padding(horizontal = 10.dp, vertical = 4.dp),
                )
            }
        }
        val l = apps
        when {
            erreur -> Text("Le PC ne repond pas.", color = Texte3, fontSize = 13.sp)
            l == null -> Text("Chargement des apps du PC...", color = Texte3, fontSize = 13.sp)
            else -> LazyVerticalGrid(
                columns = GridCells.Adaptive(84.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                items(l, key = { it.cle }) { app ->
                    CaseApp(app) {
                        scope.launch {
                            val nouveau = withContext(Dispatchers.IO) {
                                if (app.bouton == null) app.copy(bouton = Pc.ajouter(app.cle, cible))
                                else if (Pc.retirer(app.bouton)) app.copy(bouton = null) else app
                            }
                            // Un raccourci clavier retire n'est pas une app du PC : il disparait de la liste.
                            apps = if (app.cle.startsWith("deck-") && nouveau.bouton == null) apps?.filter { it.cle != app.cle }
                            else apps?.map { if (it.cle == app.cle) nouveau else it }
                            onChange()
                        }
                    }
                }
            }
        }
    }
}

// ---------- Tous les composants du PC ----------

@Composable
fun PageComposants() {
    val dossier = LocalContext.current.filesDir
    var sections by remember { mutableStateOf<List<Pair<String, List<Pair<String, String>>>>?>(null) }
    LaunchedEffect(Unit) {
        // D'abord la copie enregistree sur le telephone, puis les valeurs a jour du PC.
        withContext(Dispatchers.IO) { Pc.composantsEnregistres(dossier) }?.let { sections = it }
        while (true) {
            withContext(Dispatchers.IO) { Pc.composants(dossier) }?.let { sections = it }
            delay(3000)
        }
    }
    val brut = sections
    if (brut == null) {
        Text("Lecture des composants du PC...", color = Texte3, fontSize = 13.sp)
        return
    }
    // Les pieces importantes d'abord.
    val ordre = listOf("Carte graphique", "Processeur", "Memoire vive", "Carte mere", "Disques", "Reseau", "Systeme")
    val s = brut.sortedBy { ordre.indexOf(it.first).let { i -> if (i < 0) 99 else i } }
    var choix by rememberSaveable { mutableStateOf("Carte graphique") }
    val actuel = s.firstOrNull { it.first == choix } ?: s.first()
    val forme = RoundedCornerShape(16.dp)

    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxSize()) {
        // Liste des composants
        Column(
            verticalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.width(170.dp).fillMaxHeight(),
        ) {
            s.forEach { (titre, lignes) ->
                val actif = titre == actuel.first
                val fond by animateColorAsState(if (actif) Texte else Surface, label = "composant")
                Column(
                    verticalArrangement = Arrangement.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .clip(RoundedCornerShape(12.dp))
                        .background(fond)
                        .border(1.dp, if (actif) Color.Transparent else Trait, RoundedCornerShape(12.dp))
                        .clickable { choix = titre }
                        .padding(horizontal = 12.dp),
                ) {
                    Text(titre, color = if (actif) Color.Black else Texte, fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                    Text(
                        lignes.firstOrNull()?.second ?: "",
                        color = if (actif) Color(0xFF555555) else Texte3,
                        fontSize = 9.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
        // Fiche du composant choisi
        Column(
            Modifier.weight(1f).fillMaxHeight().clip(forme).background(Surface).border(1.dp, Trait, forme)
                .padding(14.dp),
        ) {
            Text(actuel.first.uppercase(), color = Texte3, fontSize = 9.sp, letterSpacing = 1.6.sp, fontWeight = FontWeight.Bold)
            Text(
                actuel.second.firstOrNull()?.second ?: actuel.first,
                color = Texte, fontSize = 19.sp, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(10.dp))
            LazyVerticalGrid(
                columns = GridCells.Adaptive(150.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                items(actuel.second.drop(1)) { (nom, v) ->
                    Column(
                        Modifier.fillMaxWidth().height(54.dp).clip(RoundedCornerShape(12.dp)).background(SurfaceHaute)
                            .padding(horizontal = 10.dp, vertical = 7.dp),
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text(nom, color = Texte3, fontSize = 9.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(v, color = Texte, fontSize = 13.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis, lineHeight = 14.sp)
                    }
                }
            }
        }
    }
}

@Composable
fun CaseApp(app: AppPc, onClick: () -> Unit) {
    var icone by remember(app.cle) { mutableStateOf<androidx.compose.ui.graphics.ImageBitmap?>(null) }
    LaunchedEffect(app.cle) { icone = withContext(Dispatchers.IO) { Pc.iconeApp(app.cle) } }
    val dedans = app.bouton != null
    val forme = RoundedCornerShape(14.dp)
    Box(
        Modifier
            .fillMaxWidth()
            .height(84.dp)
            .clip(forme)
            .background(if (dedans) SurfaceHaute else Surface)
            .border(1.dp, if (dedans) Vert.copy(alpha = 0.7f) else Trait, forme)
            .clickable(onClick = onClick)
            .padding(6.dp),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center, modifier = Modifier.fillMaxSize()) {
            val ic = icone
            if (ic != null) Image(ic, contentDescription = null, filterQuality = FilterQuality.High, modifier = Modifier.size(36.dp))
            else Box(Modifier.size(36.dp).clip(RoundedCornerShape(10.dp)).background(Piste))
            Spacer(Modifier.height(5.dp))
            Text(
                app.nom, color = if (dedans) Texte else Texte2, fontSize = 9.5.sp, lineHeight = 11.sp,
                maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center,
            )
        }
        if (dedans) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.align(Alignment.TopEnd).size(16.dp).clip(CircleShape).background(Vert),
            ) { Text("✓", color = Color.Black, fontSize = 10.sp, fontWeight = FontWeight.Bold) }
        }
    }
}

@Composable
fun CartePerf(
    titre: String,
    valeur: String?,
    unite: String,
    temp: Float?,
    courbe: List<Float>,
    max: Float,
    modifier: Modifier,
    couleurForcee: Color? = null,
) {
    val forme = RoundedCornerShape(20.dp)
    val derniere = courbe.lastOrNull() ?: 0f
    val couleur = couleurForcee ?: if (max == 100f) niveau(derniere / 100f) else Texte
    Column(
        modifier
            .fillMaxHeight()
            .clip(forme)
            .background(Surface)
            .border(1.dp, Trait, forme)
            .padding(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(titre, color = Texte3, fontSize = 9.sp, letterSpacing = 1.6.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            if (temp != null) {
                Text(
                    "${temp.roundToInt()}°C",
                    color = couleurTemp(temp),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.clip(CircleShape).background(SurfaceHaute).padding(horizontal = 8.dp, vertical = 2.dp),
                )
            }
        }
        Row(verticalAlignment = Alignment.Bottom) {
            Text(valeur ?: "--", color = couleurForcee ?: Texte, fontSize = 34.sp, fontWeight = FontWeight.Black)
            Spacer(Modifier.width(6.dp))
            Text(unite, color = Texte3, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(bottom = 7.dp))
        }
        Spacer(Modifier.height(6.dp))
        Courbe(courbe, max, couleur, Modifier.weight(1f).fillMaxWidth())
    }
}

@Composable
fun Courbe(valeurs: List<Float>, max: Float, couleur: Color, modifier: Modifier) {
    Canvas(modifier) {
        for (i in 1..3) {
            val y = size.height * i / 4f
            drawLine(Trait, Offset(0f, y), Offset(size.width, y), 1f)
        }
        if (valeurs.size < 2) return@Canvas
        val pas = size.width / 59f
        val decalage = (60 - valeurs.size) * pas
        val ligne = Path()
        val aire = Path()
        valeurs.forEachIndexed { i, v ->
            val x = decalage + i * pas
            val y = size.height * (1f - (v / max).coerceIn(0f, 1f))
            if (i == 0) {
                ligne.moveTo(x, y)
                aire.moveTo(x, size.height)
                aire.lineTo(x, y)
            } else {
                ligne.lineTo(x, y)
                aire.lineTo(x, y)
            }
        }
        aire.lineTo(decalage + (valeurs.size - 1) * pas, size.height)
        aire.close()
        drawPath(aire, Brush.verticalGradient(listOf(couleur.copy(alpha = 0.22f), Color.Transparent)))
        drawPath(ligne, couleur, style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

// ---------- Grille de touches (tient toujours sur l'ecran) ----------

@Composable
fun GrilleTouches(
    boutons: List<Bouton>,
    actif: Boolean,
    edition: Boolean,
    ouvertes: Set<String>,
    onEdition: () -> Unit,
    onOrdre: (List<String>) -> Unit,
    onAppui: (Bouton) -> Unit,
) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val ecart = 10.dp
        val n = boutons.size
        // Nombre de colonnes qui donne les touches les plus grandes possible.
        var colonnes = 1
        var meilleur = 0.dp
        for (c in 1..n) {
            val lignes = (n + c - 1) / c
            val l = (maxWidth - ecart * (c - 1)) / c
            val h = (maxHeight - ecart * (lignes - 1)) / lignes
            val cote: Dp = minOf(l, h * 1.15f)
            if (cote > meilleur) {
                meilleur = cote
                colonnes = c
            }
        }
        val lignes = (n + colonnes - 1) / colonnes
        val largeur = (maxWidth - ecart * (colonnes - 1)) / colonnes
        val hauteur = (maxHeight - ecart * (lignes - 1)) / lignes
        val densite = LocalDensity.current
        val pasX = with(densite) { (largeur + ecart).toPx() }
        val pasY = with(densite) { (hauteur + ecart).toPx() }
        fun origine(i: Int) = Offset((i % colonnes) * pasX, (i / colonnes) * pasY)
        fun caseSous(p: Offset): Int {
            val c = (p.x / pasX).toInt().coerceIn(0, colonnes - 1)
            val l = (p.y / pasY).toInt().coerceIn(0, lignes - 1)
            return (l * colonnes + c).coerceAtMost(n - 1)
        }

        // Ordre local (modifie en direct pendant qu'on glisse).
        val ordre = remember(boutons.map { it.id }) { mutableStateListOf(*boutons.toTypedArray()) }
        // Les icones peuvent changer sans que l'ordre change : on garde les dernieres.
        val parId = boutons.associateBy { it.id }
        var glisse by remember { mutableStateOf<String?>(null) }
        var doigt by remember { mutableStateOf(Offset.Zero) }
        var prise by remember { mutableStateOf(Offset.Zero) }
        val vue = LocalView.current

        val geste = if (!edition) Modifier else Modifier.pointerInput(colonnes, lignes, n) {
            detectDragGestures(
                onDragStart = { p ->
                    val i = caseSous(p)
                    glisse = ordre[i].id
                    prise = p - origine(i)
                    doigt = p
                    vue.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                },
                onDrag = { change, d ->
                    change.consume()
                    doigt += d
                    val id = glisse ?: return@detectDragGestures
                    val actuel = ordre.indexOfFirst { it.id == id }
                    val centre = doigt - prise + Offset(pasX / 2f, pasY / 2f)
                    val cible = caseSous(centre)
                    if (actuel >= 0 && cible != actuel) ordre.add(cible, ordre.removeAt(actuel))
                },
                onDragEnd = {
                    glisse = null
                    onOrdre(ordre.map { it.id })
                },
                onDragCancel = { glisse = null },
            )
        }

        Box(Modifier.fillMaxSize().then(geste)) {
            ordre.forEachIndexed { i, b0 ->
                val b = parId[b0.id] ?: b0
                key(b.id) {
                    val enMain = glisse == b.id
                    val place by animateIntOffsetAsState(origine(i).round(), label = "place")
                    val pos = if (enMain) (doigt - prise).round() else place
                    Box(
                        Modifier
                            .offset { pos }
                            .size(largeur, hauteur)
                            .zIndex(if (enMain) 1f else 0f)
                            .graphicsLayer {
                                val e = if (enMain) 1.08f else 1f
                                scaleX = e; scaleY = e
                                alpha = if (enMain) 0.92f else 1f
                            },
                    ) {
                        Touche(b, actif && !edition, edition, b.id in ouvertes, onLong = onEdition) { onAppui(b) }
                    }
                }
            }
        }
    }
}

@Composable
fun Touche(b: Bouton, actif: Boolean, edition: Boolean, ouverte: Boolean, onLong: () -> Unit, onAppui: () -> Unit) {
    val vue = LocalView.current
    var appuye by remember { mutableStateOf(false) }
    val actuel by rememberUpdatedState(onAppui)
    val long by rememberUpdatedState(onLong)
    val echelle by animateFloatAsState(if (appuye) 0.95f else 1f, animationSpec = tween(70), label = "echelle")
    val forme = RoundedCornerShape(20.dp)
    val teinte = b.couleur?.let { Color(it) }
    val fond = when {
        appuye -> SurfaceHaute
        teinte != null -> teinte.copy(alpha = 0.22f)
        else -> Surface
    }
    val bord = when {
        edition -> Texte.copy(alpha = 0.55f)
        appuye -> Texte.copy(alpha = 0.4f)
        teinte != null -> teinte.copy(alpha = 0.9f)
        else -> Trait
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val icone = minOf(maxWidth * 0.5f, maxHeight * 0.5f)
        val texte = (maxHeight.value * 0.095f).coerceIn(9f, 12.5f).sp
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .scale(echelle)
                .fillMaxSize()
                .clip(forme)
                .background(fond)
                .border(if (edition) 1.5.dp else 1.dp, bord, forme)
                // Lance quand le doigt se releve ; appui long = organiser les icones.
                .pointerInput(actif) {
                    if (!actif) return@pointerInput
                    detectTapGestures(
                        onPress = {
                            appuye = true
                            tryAwaitRelease()
                            appuye = false
                        },
                        onTap = {
                            vue.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                            actuel()
                        },
                        onLongPress = {
                            vue.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                            long()
                        },
                    )
                }
                .padding(8.dp),
        ) {
            if (b.icone != null) {
                Image(b.icone, contentDescription = null, filterQuality = FilterQuality.High, modifier = Modifier.size(icone))
            } else {
                // Touche clavier sans icone : initiales dans un carre arrondi.
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .size(icone)
                        .clip(RoundedCornerShape(icone * 0.28f))
                        .background(if (teinte != null) teinte.copy(alpha = 0.5f) else SurfaceHaute),
                ) {
                    Text(b.nom.take(2).uppercase(), color = Texte, fontSize = (icone.value * 0.34f).sp, fontWeight = FontWeight.Bold)
                }
            }
            Spacer(Modifier.height(7.dp))
            Text(
                b.nom,
                color = Texte2,
                fontSize = texte,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
            )
        }
        // App ouverte sur le PC : pastille verte (un appui la fermera).
        if (ouverte) {
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .padding(10.dp)
                    .size(9.dp)
                    .clip(CircleShape)
                    .background(Vert),
            )
        }
    }
}
// ---------- Formats ----------

private fun un(v: Float) = String.format(Locale.FRANCE, "%.1f", v)

private fun debit(ko: Float) =
    if (ko >= 1024f) String.format(Locale.FRANCE, "%.1f Mo/s", ko / 1024f) else "${ko.roundToInt()} Ko/s"
