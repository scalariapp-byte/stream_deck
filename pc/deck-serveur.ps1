# Serveur Deck : recoit les appuis du telephone (Redmi) branche en USB.
# Le telephone parle a http://localhost:8765 ; "adb reverse" fait passer ca par le cable.
# Les boutons sont dans deck.json (cree automatiquement au premier lancement
# a partir des raccourcis du Bureau). Modifie deck.json : le telephone se met a jour tout seul.

$Port    = 8765
$Dossier = $PSScriptRoot
$Config  = Join-Path $Dossier 'deck.json'
$Icones  = Join-Path $Dossier 'icones'
$Adb     = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
New-Item -ItemType Directory -Force $Icones | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

// Icones en grand (256 px, avec transparence) via le Shell de Windows.
public static class DeckIcone {
  [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IShellItemImageFactory { void GetImage(TAILLE size, int flags, out IntPtr phbm); }
  [StructLayout(LayoutKind.Sequential)] struct TAILLE { public int cx; public int cy; }
  [StructLayout(LayoutKind.Sequential)] struct BITMAP {
    public int bmType, bmWidth, bmHeight, bmWidthBytes; public ushort bmPlanes, bmBitsPixel; public IntPtr bmBits;
  }
  [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
  static extern void SHCreateItemFromParsingName(string path, IntPtr pbc, [MarshalAs(UnmanagedType.LPStruct)] Guid riid,
    [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory ppv);
  [DllImport("gdi32.dll")] static extern int GetObject(IntPtr h, int c, out BITMAP b);
  [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr h);

  public static void Enregistrer(string chemin, int taille, string png) {
    IShellItemImageFactory f;
    SHCreateItemFromParsingName(chemin, IntPtr.Zero, typeof(IShellItemImageFactory).GUID, out f);
    IntPtr hbm;
    f.GetImage(new TAILLE { cx = taille, cy = taille }, 0x4 /* icone seule */, out hbm);
    try {
      BITMAP b; GetObject(hbm, Marshal.SizeOf(typeof(BITMAP)), out b);
      using (var brut = new Bitmap(b.bmWidth, b.bmHeight, b.bmWidthBytes, PixelFormat.Format32bppPArgb, b.bmBits))
      using (var copie = new Bitmap(b.bmWidth, b.bmHeight, PixelFormat.Format32bppArgb)) {
        using (var g = Graphics.FromImage(copie)) g.DrawImage(brut, 0, 0, b.bmWidth, b.bmHeight);
        // Image stockee de bas en haut (hauteur positive) : on la remet a l'endroit.
        if (b.bmHeight > 0) copie.RotateFlip(RotateFlipType.RotateNoneFlipY);
        using (var net = Recadrer(copie)) net.Save(png, ImageFormat.Png);
      }
    } finally { DeleteObject(hbm); }
  }

  // Enleve le vide transparent autour du dessin et le remet a 256 px :
  // toutes les icones ont ainsi la meme taille a l'ecran.
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  static extern uint PrivateExtractIcons(string f, int i, int cx, int cy, IntPtr[] h, uint[] id, uint n, uint fl);
  [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr h);

  // Icone tiree directement du programme (sa plus grande image), recadree. Renvoie la taille du dessin.
  public static int DepuisExe(string exe, string png) {
    var h = new IntPtr[1]; var id = new uint[1];
    if (PrivateExtractIcons(exe, 0, 256, 256, h, id, 1, 0) == 0 || h[0] == IntPtr.Zero) return 0;
    try {
      using (var ic = Icon.FromHandle(h[0])) using (var bmp = ic.ToBitmap()) using (var net = Recadrer(bmp)) {
        net.Save(png, ImageFormat.Png);
        return DerniereTaille;
      }
    } finally { DestroyIcon(h[0]); }
  }

  // Taille reelle du dessin (en px) dans la derniere icone recadree.
  public static int DerniereTaille = 0;

  public static Bitmap Recadrer(Bitmap src) {
    int x0 = src.Width, y0 = src.Height, x1 = -1, y1 = -1;
    for (int y = 0; y < src.Height; y++)
      for (int x = 0; x < src.Width; x++)
        if (src.GetPixel(x, y).A > 100) { // ignore les ombres legeres
          if (x < x0) x0 = x; if (x > x1) x1 = x;
          if (y < y0) y0 = y; if (y > y1) y1 = y;
        }
    const int T = 256;
    DerniereTaille = x1 < 0 ? 0 : Math.Max(x1 - x0 + 1, y1 - y0 + 1);
    var res = new Bitmap(T, T, PixelFormat.Format32bppArgb);
    if (x1 < 0) { using (var g = Graphics.FromImage(res)) g.DrawImage(src, 0, 0, T, T); return res; }
    int w = x1 - x0 + 1, h = y1 - y0 + 1;
    float marge = T * 0.04f;
    float echelle = (T - 2 * marge) / Math.Max(w, h);
    float dw = w * echelle, dh = h * echelle;
    using (var g = Graphics.FromImage(res)) {
      g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
      g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
      g.DrawImage(src, new RectangleF((T - dw) / 2, (T - dh) / 2, dw, dh), new RectangleF(x0, y0, w, h), GraphicsUnit.Pixel);
    }
    return res;
  }
}

// Lance une app dans un fil a part, en mode "STA" comme l'Explorateur :
// un raccourci lent a s'ouvrir ne bloque plus les appuis suivants.
public static class DeckLance {
  public static void Lancer(string cible) {
    var t = new System.Threading.Thread(() => {
      try {
        var psi = new System.Diagnostics.ProcessStartInfo(cible);
        psi.UseShellExecute = true;
        System.Diagnostics.Process.Start(psi);
      } catch (Exception e) { Erreur = cible + " : " + e.Message; }
    });
    t.SetApartmentState(System.Threading.ApartmentState.STA);
    t.IsBackground = true;
    t.Start();
  }
  public static string Erreur = "";
}

// Ferme une app poliment (comme la croix de la fenetre). Si elle demande d'enregistrer,
// on ne force rien : sa fenetre passe devant pour que tu repondes.
public static class DeckFerme {
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  public static void Fermer(int[] pids) {
    var t = new System.Threading.Thread(() => {
      var ps = new System.Collections.Generic.List<System.Diagnostics.Process>();
      foreach (var id in pids) { try { ps.Add(System.Diagnostics.Process.GetProcessById(id)); } catch { } }
      foreach (var p in ps) { try { p.CloseMainWindow(); } catch { } }
      var fin = DateTime.Now.AddSeconds(3);
      while (DateTime.Now < fin && ps.Exists(p => { try { return !p.HasExited; } catch { return false; } }))
        System.Threading.Thread.Sleep(200);
      // Encore une fenetre ouverte : l'app demande sans doute d'enregistrer.
      foreach (var p in ps) {
        try {
          if (p.HasExited) continue;
          p.Refresh();
          var h = p.MainWindowHandle;
          if (h != IntPtr.Zero) {
            if (IsIconic(h)) ShowWindow(h, 9);
            keybd_event(0x12, 0, 0, UIntPtr.Zero); keybd_event(0x12, 0, 2, UIntPtr.Zero);
            SetForegroundWindow(h);
            return;
          }
        } catch { }
      }
      // Plus aucune fenetre : il ne reste que des processus de fond, on les arrete.
      foreach (var p in ps) { try { if (!p.HasExited) p.Kill(); } catch { } }
    });
    t.IsBackground = true;
    t.Start();
  }
}

public static class DeckClavier {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
}
"@

# ---------- Clavier ----------
$NomsTouches = @{
  CTRL=0x11; SHIFT=0x10; ALT=0x12; WIN=0x5B; ESC=0x1B; TAB=0x09; ENTREE=0x0D; ESPACE=0x20
  SUPPR=0x2E; RETOUR=0x08; HAUT=0x26; BAS=0x28; GAUCHE=0x25; DROITE=0x27; IMPR=0x2C
  DEBUT=0x24; FIN=0x23; PGHAUT=0x21; PGBAS=0x22
}
1..12 | ForEach-Object { $NomsTouches["F$_"] = 0x6F + $_ }
$Etendues = @(0x5B,0x2E,0x26,0x28,0x25,0x27,0x24,0x23,0x21,0x22,0x2C)

function Code-Touche([string]$nom) {
  $n = $nom.Trim().ToUpper()
  if ($NomsTouches.ContainsKey($n)) { return [byte]$NomsTouches[$n] }
  if ($n.Length -eq 1 -and $n -match '[A-Z0-9]') { return [byte][char]$n }
  throw "Touche inconnue : $nom"
}

function Envoyer-Touches([string]$combo) {
  $codes = @($combo.Split('+') | ForEach-Object { Code-Touche $_ })
  foreach ($c in $codes) {
    $f = if ($Etendues -contains $c) { 1 } else { 0 }
    [DeckClavier]::keybd_event($c, 0, $f, [UIntPtr]::Zero)
  }
  [array]::Reverse($codes)
  foreach ($c in $codes) {
    $f = if ($Etendues -contains $c) { 3 } else { 2 }
    [DeckClavier]::keybd_event($c, 0, $f, [UIntPtr]::Zero)
  }
}

# ---------- Configuration ----------
function Nouvelle-Config {
  $boutons = New-Object System.Collections.ArrayList
  $n = 0
  $bureaux = @([Environment]::GetFolderPath('Desktop'), (Join-Path $env:PUBLIC 'Desktop'))
  foreach ($b in $bureaux) {
    Get-ChildItem $b -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Extension -in '.lnk','.url' } | Sort-Object BaseName |
      ForEach-Object {
        $n++
        [void]$boutons.Add([ordered]@{ id="b$n"; nom=$_.BaseName; type='app'; cible=$_.FullName })
      }
  }
  $raccourcis = @(
    @('Capture', 'WIN+SHIFT+S'), @('Bureau', 'WIN+D'), @('Changer fenetre', 'ALT+TAB'),
    @('Gestionnaire', 'CTRL+SHIFT+ESC'), @('Copier', 'CTRL+C'), @('Coller', 'CTRL+V')
  )
  foreach ($r in $raccourcis) {
    $n++
    [void]$boutons.Add([ordered]@{ id="b$n"; nom=$r[0]; type='touches'; cible=$r[1]; couleur='#2B2B2B' })
  }
  $cfg = [ordered]@{ colonnes = 7; boutons = $boutons }
  $cfg | ConvertTo-Json -Depth 4 | Set-Content $Config -Encoding UTF8
}

function Lire-Config {
  if (-not (Test-Path $Config)) { Nouvelle-Config }
  return (Get-Content $Config -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Version-Config { (Get-Item $Config).LastWriteTimeUtc.Ticks.ToString() }

# ---------- Icones ----------
function Icone-Png($b) {
  $png = Join-Path $Icones "$($b.id).png"
  if (Test-Path $png) { return $png }
  if ($b.type -notin 'app','chrome') { return $null }
  # "iconeSource" dans deck.json : fichier d'ou tirer l'icone (apps du Store, etc.).
  $src = if ($b.iconeSource) { $b.iconeSource } else { $b.cible }
  return (Icone-Fichier $src $png $b.nom)
}

function Icone-Fichier([string]$src, [string]$png, [string]$nom) {
  if (Test-Path $png) { return $png }
  try {
    if ($src -like '*.lnk') {
      $l = (New-Object -ComObject WScript.Shell).CreateShortcut($src)
      $ic = ($l.IconLocation -split ',')[0]
      if ($ic -and (Test-Path $ic)) { $src = $ic }
      elseif ($l.TargetPath -and (Test-Path $l.TargetPath)) { $src = $l.TargetPath }
    } elseif ($src -like '*.url') {
      $ligne = Get-Content $src | Where-Object { $_ -like 'IconFile=*' } | Select-Object -First 1
      if ($ligne -and (Test-Path $ligne.Substring(9))) { $src = $ligne.Substring(9) }
    }
    if ($src -notlike 'shell:*') { $src = $src -replace '/', '\' }
    # D'abord en grand (256 px) par le Shell ; sinon l'ancienne methode (32 px).
    try {
      [DeckIcone]::Enregistrer($src, 256, $png)
      # Dessin trop petit (le programme n'a qu'une petite icone) : on cherche une vraie image en grand.
      if ([DeckIcone]::DerniereTaille -lt 128 -and $src -like '*.exe') {
        $petite = [DeckIcone]::DerniereTaille
        if (-not (Icone-Grande $src $png)) {
          # Sinon, la plus grande image rangee dans le programme lui-meme (souvent mieux que celle du Shell).
          $tmp = "$png.exe.png"
          if ([DeckIcone]::DepuisExe($src, $tmp) -gt $petite) { Move-Item $tmp $png -Force } else { Remove-Item $tmp -ErrorAction SilentlyContinue }
        }
      }
      return $png
    } catch { $script:ErreurIcone = "$nom [$src] : $($_.Exception.InnerException.Message) $($_.Exception.Message)" }
    if ($src -like '*.ico') { $bmp = (New-Object System.Drawing.Icon($src, 256, 256)).ToBitmap() }
    else { $bmp = [System.Drawing.Icon]::ExtractAssociatedIcon($src).ToBitmap() }
    $net = [DeckIcone]::Recadrer($bmp)
    $net.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
    return $png
  } catch { return $null }
}

# Cherche dans le dossier du programme une image carree d'au moins 128 px
# au nom du programme, "AppIcon" ou "logo" ; la plus grande gagne.
function Icone-Grande([string]$exe, [string]$png) {
  $dossier = Split-Path $exe
  if ($dossier -match '^[A-Z]:\\(Windows)?$') { return $false }
  $base = ([IO.Path]::GetFileNameWithoutExtension($exe) -replace '[^A-Za-z0-9]', '').ToLower()
  $meilleur = $null; $score = 0
  $fichiers = Get-ChildItem $dossier -Recurse -Depth 3 -Include *.png, *.ico -ErrorAction SilentlyContinue | Select-Object -First 3000
  foreach ($f in $fichiers) {
    $nom = ($f.BaseName -replace '[^A-Za-z0-9]', '').ToLower()
    if ($nom -match 'gray|grey|dark|mac|title|disabled|small|tray') { continue }
    $prio = if ($base.Length -ge 4 -and $nom.Contains($base)) { 3 } elseif ($nom -like 'appicon*') { 2 } elseif ($nom -like 'logo*') { 1 } else { 0 }
    if ($prio -eq 0) { continue }
    try {
      $img = if ($f.Extension -eq '.ico') { (New-Object System.Drawing.Icon($f.FullName, 256, 256)).ToBitmap() } else { New-Object System.Drawing.Bitmap $f.FullName }
      $w = $img.Width; $h = $img.Height; $img.Dispose()
    } catch { continue }
    if ($w -lt 128 -or [math]::Abs($w - $h) -gt $w * 0.1) { continue }
    $s = $prio * 10000 + [math]::Min($w, 1024)
    if ($s -gt $score) { $score = $s; $meilleur = $f.FullName }
  }
  if (-not $meilleur) { return $false }
  $img = if ($meilleur -like '*.ico') { (New-Object System.Drawing.Icon($meilleur, 256, 256)).ToBitmap() } else { New-Object System.Drawing.Bitmap $meilleur }
  $net = [DeckIcone]::Recadrer($img); $img.Dispose()
  $net.Save($png, [System.Drawing.Imaging.ImageFormat]::Png); $net.Dispose()
  return $true
}

# ---------- Apps du PC (pour l'ajout depuis le telephone) ----------
$IconesApps = Join-Path $Icones 'apps'
New-Item -ItemType Directory -Force $IconesApps | Out-Null
$script:AppsPc = @{}   # cle -> @{ nom; cible }

function Cle-Texte([string]$t) {
  $md5 = [Security.Cryptography.MD5]::Create()
  return (-join ($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($t.ToLower())) | Select-Object -First 6 | ForEach-Object { $_.ToString('x2') }))
}

function Apps-Pc {
  $vu = @{}
  $liste = New-Object System.Collections.ArrayList
  $exclus = 'uninstall|d.sinstall|readme|lisez|help|aide|documentation|manual|manuel|site web|website|release notes|license|licence'
  foreach ($a in Get-StartApps) {
    if ($a.Name -match $exclus -or $vu.ContainsKey($a.Name.ToLower())) { continue }
    $vu[$a.Name.ToLower()] = 1
    [void]$liste.Add(@{ nom = $a.Name; cible = "shell:AppsFolder\$($a.AppID)" })
  }
  foreach ($d in @([Environment]::GetFolderPath('Desktop'), (Join-Path $env:PUBLIC 'Desktop'))) {
    Get-ChildItem $d -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.lnk','.url' } | ForEach-Object {
      if (-not $vu.ContainsKey($_.BaseName.ToLower())) {
        $vu[$_.BaseName.ToLower()] = 1
        [void]$liste.Add(@{ nom = $_.BaseName; cible = $_.FullName })
      }
    }
  }
  $script:AppsPc = @{}
  foreach ($a in $liste) { $script:AppsPc[(Cle-Texte $a.cible)] = $a }
  return $liste
}

function Sauver-Config($cfg) {
  Copy-Item $Config "$Config.sauve" -Force
  $cfg | ConvertTo-Json -Depth 6 | Set-Content $Config -Encoding UTF8
}

# ---------- Details des performances (page ouverte en touchant une case) ----------
function Lhm-Capteurs {
  $res = @{}
  try {
    $lhm = Invoke-RestMethod 'http://localhost:8085/data.json' -TimeoutSec 1 -UseBasicParsing
    $pile = New-Object System.Collections.Stack
    $pile.Push($lhm)
    while ($pile.Count -gt 0) {
      $n = $pile.Pop()
      foreach ($c in @($n.Children)) { if ($c) { $pile.Push($c) } }
      if (-not $n.SensorId) {
        # Nom du materiel : "/nvme/2" -> "CT1000P3SSD8" (vu par ses capteurs, deux niveaux plus bas).
        $sous = @($n.Children | ForEach-Object { @($_.Children) } | Where-Object { $_.SensorId } | Select-Object -First 1)
        if ($sous.Count -and $sous[0].SensorId -match '^(/[^/]+/[^/]+)/') { $res["nom" + $Matches[1]] = $n.Text }
        if ($n.ImageURL -like '*cpu*') { $res['nomCpu'] = $n.Text }
        if ($n.ImageURL -like '*ati*' -or $n.ImageURL -like '*nvidia*' -or $n.ImageURL -like '*gpu*') { $res['nomGpu'] = $n.Text }
        continue
      }
      $txt = [regex]::Match([string]$n.Value, '-?\d+([.,]\d+)?').Value -replace ',', '.'
      if ($txt) { $res[$n.SensorId] = @{ t = $n.Text; v = [double]::Parse($txt, [Globalization.CultureInfo]::InvariantCulture) } }
    }
  } catch {}
  return $res
}

# ---------- Tous les composants du PC ----------
# La partie fixe (modeles, pilotes...) est lue une seule fois ; les mesures a chaque appel.
$script:Fixes = $null
function Composants-Fixes {
  if ($script:Fixes) { return $script:Fixes }
  $f = [ordered]@{}
  $os = Get-CimInstance Win32_OperatingSystem
  $cs = Get-CimInstance Win32_ComputerSystem
  $f.systeme = @(
    (L 'Systeme' $os.Caption), (L 'Version' "$($os.Version) (build $($os.BuildNumber))"),
    (L 'Nom du PC' $cs.Name), (L 'Installe le' $os.InstallDate.ToString('dd/MM/yyyy')))
  $bb = Get-CimInstance Win32_BaseBoard; $bios = Get-CimInstance Win32_BIOS
  $f.cm = @((L 'Fabricant' $bb.Manufacturer), (L 'Modele' $bb.Product), (L 'BIOS' $bios.SMBIOSBIOSVersion),
    (L 'Date du BIOS' $(if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString('dd/MM/yyyy') })))
  $p = Get-CimInstance Win32_Processor | Select-Object -First 1
  $f.cpu = @((L 'Modele' $p.Name.Trim()), (L 'Coeurs / threads' "$($p.NumberOfCores) / $($p.NumberOfLogicalProcessors)"),
    (L 'Frequence de base' ("{0:N2} GHz" -f ($p.MaxClockSpeed / 1000))), (L 'Cache L2' ("{0:N0} Ko" -f $p.L2CacheSize)),
    (L 'Cache L3' ("{0:N0} Mo" -f ($p.L3CacheSize / 1024))), (L 'Socket' $p.SocketDesignation))
  $f.gpu = @()
  foreach ($v in Get-CimInstance Win32_VideoController) {
    $f.gpu += L 'Modele' $v.Name
    $f.gpu += L 'Pilote' $v.DriverVersion
    if ($v.DriverDate) { $f.gpu += L 'Date du pilote' $v.DriverDate.ToString('dd/MM/yyyy') }
    if ($v.CurrentHorizontalResolution) { $f.gpu += L 'Ecran' "$($v.CurrentHorizontalResolution) x $($v.CurrentVerticalResolution) a $($v.CurrentRefreshRate) Hz" }
  }
  $f.gpu += L 'Memoire video' "$($Perf.vramTotal) Go"
  $f.ram = @()
  $mods = @(Get-CimInstance Win32_PhysicalMemory)
  $f.ram += L 'Total' ("{0:N0} Go en {1} barrettes" -f (($mods | Measure-Object Capacity -Sum).Sum / 1GB), $mods.Count)
  foreach ($m in $mods) {
    $f.ram += L ("$($m.BankLabel) $($m.DeviceLocator)".Trim()) ("{0:N0} Go {1} MT/s {2}" -f ($m.Capacity / 1GB), $m.ConfiguredClockSpeed, ([string]$m.PartNumber).Trim())
  }
  $f.disques = @()
  foreach ($d in Get-PhysicalDisk | Sort-Object DeviceId) {
    $f.disques += L $d.FriendlyName ("{0:N0} Go, {1} {2}" -f ($d.Size / 1GB), $d.MediaType, $d.BusType)
  }
  $script:Fixes = $f
  return $f
}

function Composants {
  $f = Composants-Fixes
  $s = Lhm-Capteurs
  function V($id) { if ($s.ContainsKey($id)) { $s[$id].v } else { $null } }
  $sections = New-Object System.Collections.ArrayList
  function Section($titre, $lignes) { [void]$sections.Add([ordered]@{ titre = $titre; lignes = @($lignes | Where-Object { $_ -and $_.valeur }) }) }

  $os = Get-CimInstance Win32_OperatingSystem
  $marche = (Get-Date) - $os.LastBootUpTime
  Section 'Systeme' ($f.systeme + (L 'Allume depuis' ("{0} j {1} h {2} min" -f $marche.Days, $marche.Hours, $marche.Minutes)))

  $cpu = @($f.cpu) + (L 'Utilisation' "$($Perf.cpu) %")
  if ($null -ne $Perf.cpuTemp) { $cpu += L 'Temperature' "$($Perf.cpuTemp) °C" }
  $c = V '/amdcpu/0/clock/1'; if ($c) { $cpu += L 'Frequence actuelle' ("{0:N2} GHz" -f ($c / 1000)) }
  $c = V '/amdcpu/0/clock/0'; if ($c) { $cpu += L 'Bus' ("{0:N1} MHz" -f $c) }
  Section 'Processeur' $cpu

  $gpu = @($f.gpu) + (L 'Utilisation' "$($Perf.gpu) %") + (L 'Memoire utilisee' ("{0:N1} Go" -f $Perf.vram))
  if ($null -ne $Perf.gpuTemp) { $gpu += L 'Temperature' "$($Perf.gpuTemp) °C" }
  $c = V '/gpu-amd/0/clock/0'; if ($null -ne $c) { $gpu += L 'Frequence coeur' ("{0:N0} MHz" -f $c) }
  $c = V '/gpu-amd/0/clock/2'; if ($null -ne $c) { $gpu += L 'Frequence memoire' ("{0:N0} MHz" -f $c) }
  $c = V '/gpu-amd/0/power/3'; if ($null -ne $c) { $gpu += L 'Consommation' ("{0:N0} W" -f $c) }
  $c = V '/gpu-amd/0/voltage/0'; if ($null -ne $c) { $gpu += L 'Tension' ("{0:N3} V" -f $c) }
  $c = V '/gpu-amd/0/fan/0'; if ($null -ne $c) { $gpu += L 'Ventilateur' ("{0:N0} tr/min" -f $c) }
  $c = V '/gpu-amd/0/control/0'; if ($null -ne $c) { $gpu += L 'Ventilateur (%)' ("{0:N0} %" -f $c) }
  Section 'Carte graphique' $gpu

  Section 'Memoire vive' (@($f.ram) + (L 'Utilisee' ("{0:N1} Go" -f $Perf.ram)) + (L 'Libre' ("{0:N1} Go" -f ($Perf.ramTotal - $Perf.ram))))
  Section 'Carte mere' $f.cm

  $dq = @($f.disques)
  # Une temperature par disque : la premiere de chacun.
  $temps = $s.Keys | Where-Object { $_ -match '^/(hdd|nvme|ssd|storage)/[^/]+/temperature/' } | Sort-Object |
    Group-Object { ($_ -split '/')[1..2] -join '/' }
  foreach ($gr in $temps) {
    $k = $gr.Group | Sort-Object { [int](($_ -split '/')[-1]) } | Select-Object -First 1
    $nom = $s["nom/$($gr.Name)"]; if (-not $nom) { $nom = $gr.Name }
    $dq += L "Temp. $nom" ("{0:N0} °C" -f $s[$k].v)
  }
  foreach ($v in Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.Size -gt 0 } | Sort-Object DriveLetter) {
    $dq += L "$($v.DriveLetter): $($v.FileSystemLabel)" ("{0:N0} Go libres sur {1:N0}" -f ($v.SizeRemaining / 1GB), ($v.Size / 1GB))
  }
  Section 'Disques' $dq

  $net = @()
  foreach ($a in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')) {
    $net += L $a.Name "$($a.InterfaceDescription)"
    $net += L 'Vitesse' "$($a.LinkSpeed)"
    $ip = (Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
    if ($ip) { $net += L 'Adresse IP' $ip }
    $net += L 'Adresse MAC' $a.MacAddress
  }
  $net += L 'Reception' ("{0:N0} Ko/s" -f $Perf.netIn)
  $net += L 'Envoi' ("{0:N0} Ko/s" -f $Perf.netOut)
  $net += L 'Ping' $(if ($Perf.ping -ge 0) { "$($Perf.ping) ms" } else { 'pas de reponse' })
  Section 'Reseau' $net
  return [ordered]@{ sections = @($sections) }
}

function L($nom, $valeur) { [ordered]@{ nom = $nom; valeur = "$valeur" } }
function Barre($nom, [double]$part, $texte) { [ordered]@{ nom = $nom; part = [math]::Round([math]::Max(0, [math]::Min(1, $part)), 3); texte = "$texte" } }

function Top-Processus([string]$propriete, [int]$nb) {
  Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin '_Total', 'Idle' } |
    Group-Object { $_.Name -replace '#\d+$', '' } |
    ForEach-Object { [pscustomobject]@{ nom = $_.Name; v = ($_.Group | Measure-Object $propriete -Sum).Sum } } |
    Sort-Object v -Descending | Select-Object -First $nb
}

function Details([string]$cle) {
  $s = Lhm-Capteurs
  function V($id) { if ($s.ContainsKey($id)) { $s[$id].v } else { $null } }
  $lignes = @(); $barres = @(); $titreBarres = ''
  switch ($cle) {
    'cpu' {
      $lignes += L 'Modele' $s['nomCpu']
      $lignes += L 'Utilisation' "$($Perf.cpu) %"
      if ($null -ne $Perf.cpuTemp) { $lignes += L 'Temperature' "$($Perf.cpuTemp) °C" }
      $moy = V '/amdcpu/0/clock/1'; if ($moy) { $lignes += L 'Frequence moyenne' ("{0:N2} GHz" -f ($moy / 1000)) }
      $max = ($s.Keys | Where-Object { $_ -like '/amdcpu/0/clock/*' -and $s[$_].t -match '^Core #\d+$' } | ForEach-Object { $s[$_].v } | Measure-Object -Maximum).Maximum
      if ($max) { $lignes += L 'Frequence max' ("{0:N2} GHz" -f ($max / 1000)) }
      $nbProc = (Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Measure-Object).Count
      $lignes += L 'Processus' $nbProc
      $titreBarres = 'Coeurs'
      $coeurs = $s.Keys | Where-Object { $_ -like '/amdcpu/0/load/*' -and $s[$_].t -match '^CPU Core #(\d+)$' } |
        Sort-Object { [int]([regex]::Match($s[$_].t, '\d+$').Value) }
      foreach ($k in $coeurs) { $v = $s[$k].v; $barres += Barre ($s[$k].t -replace 'CPU Core #', '') ($v / 100) ("{0:N0} %" -f $v) }
      if ($barres.Count -eq 0) {
        $titreBarres = 'Programmes'
        $nbCoeurs = [Environment]::ProcessorCount
        foreach ($p in Top-Processus 'PercentProcessorTime' 6) { $barres += Barre $p.nom ($p.v / 100 / $nbCoeurs) ("{0:N0} %" -f ($p.v / $nbCoeurs)) }
      }
    }
    'gpu' {
      $lignes += L 'Modele' $s['nomGpu']
      $lignes += L 'Utilisation' "$($Perf.gpu) %"
      if ($null -ne $Perf.gpuTemp) { $lignes += L 'Temperature' "$($Perf.gpuTemp) °C" }
      $c = V '/gpu-amd/0/clock/0'; if ($null -ne $c) { $lignes += L 'Frequence coeur' ("{0:N0} MHz" -f $c) }
      $c = V '/gpu-amd/0/clock/2'; if ($null -ne $c) { $lignes += L 'Frequence memoire' ("{0:N0} MHz" -f $c) }
      $c = V '/gpu-amd/0/power/3'; if ($null -ne $c) { $lignes += L 'Consommation' ("{0:N0} W" -f $c) }
      $c = V '/gpu-amd/0/fan/0'; if ($null -ne $c) { $lignes += L 'Ventilateur' ("{0:N0} tr/min" -f $c) }
      $c = V '/gpu-amd/0/voltage/0'; if ($null -ne $c) { $lignes += L 'Tension' ("{0:N3} V" -f $c) }
      $titreBarres = 'Moteurs'
      $moteurs = @{}
      Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction SilentlyContinue | ForEach-Object {
        $t = [regex]::Match($_.Name, 'engtype_(.+)$').Groups[1].Value
        if ($t) { $moteurs[$t] = [double]$moteurs[$t] + $_.UtilizationPercentage }
      }
      $noms = [ordered]@{ '3D' = '3D'; 'Compute' = 'Calcul'; 'Copy' = 'Copie'; 'VideoDecode' = 'Video (lecture)'; 'VideoEncode' = 'Video (enreg.)' }
      foreach ($k in $noms.Keys) {
        $v = ($moteurs.Keys | Where-Object { $_ -like "$k*" } | ForEach-Object { $moteurs[$_] } | Measure-Object -Sum).Sum
        $v = [math]::Min(100, [double]$v)
        $barres += Barre $noms[$k] ($v / 100) ("{0:N0} %" -f $v)
      }
    }
    'ram' {
      $lignes += L 'Utilisee' ("{0:N1} Go" -f $Perf.ram)
      $lignes += L 'Libre' ("{0:N1} Go" -f ($Perf.ramTotal - $Perf.ram))
      $lignes += L 'Total' "$($Perf.ramTotal) Go"
      $barrettes = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
      if ($barrettes.Count) {
        $lignes += L 'Barrettes' ("{0} x {1:N0} Go" -f $barrettes.Count, ($barrettes[0].Capacity / 1GB))
        $lignes += L 'Vitesse' "$($barrettes[0].ConfiguredClockSpeed) MT/s"
      }
      $titreBarres = 'Programmes'
      $top = @(Top-Processus 'WorkingSetPrivate' 7)
      $m = [math]::Max(1, $top[0].v); foreach ($p in $top) { $barres += Barre $p.nom ($p.v / $m) ("{0:N1} Go" -f ($p.v / 1GB)) }
    }
    'vram' {
      $lignes += L 'Carte' $s['nomGpu']
      $lignes += L 'Utilisee' ("{0:N1} Go" -f $Perf.vram)
      $lignes += L 'Total' "$($Perf.vramTotal) Go"
      $part = (Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory -ErrorAction SilentlyContinue | Measure-Object SharedUsage -Sum).Sum
      if ($part) { $lignes += L 'Memoire partagee' ("{0:N1} Go" -f ($part / 1GB)) }
      $titreBarres = 'Programmes'
      $parPid = @{}
      Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory -ErrorAction SilentlyContinue | ForEach-Object {
        $id = [regex]::Match($_.Name, '^pid_(\d+)').Groups[1].Value
        if ($id) { $parPid[[int]$id] = [double]$parPid[[int]$id] + $_.DedicatedUsage }
      }
      $parNom = @{}
      foreach ($id in $parPid.Keys) {
        $n = (Get-Process -Id $id -ErrorAction SilentlyContinue).ProcessName
        if ($n) { $parNom[$n] = [double]$parNom[$n] + $parPid[$id] }
      }
      $top = @($parNom.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 7)
      $m = if ($top.Count) { [math]::Max(1, $top[0].Value) } else { 1 }
      foreach ($p in $top) { $barres += Barre $p.Key ($p.Value / $m) ("{0:N2} Go" -f ($p.Value / 1GB)) }
    }
    'reseau' {
      $lignes += L 'Reception' ("{0:N0} Ko/s" -f $Perf.netIn)
      $lignes += L 'Envoi' ("{0:N0} Ko/s" -f $Perf.netOut)
      $lignes += L 'Ping (1.1.1.1)' $(if ($Perf.ping -ge 0) { "$($Perf.ping) ms" } else { 'pas de reponse' })
      foreach ($a in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')) {
        $lignes += L $a.Name "$($a.LinkSpeed)"
        $ip = (Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
        if ($ip) { $lignes += L "Adresse ($($a.Name))" $ip }
        $st = (Get-NetAdapterStatistics -Name $a.Name -ErrorAction SilentlyContinue)
        if ($st) { $lignes += L "Recu depuis le demarrage" ("{0:N1} Go" -f ($st.ReceivedBytes / 1GB)); $lignes += L "Envoye depuis le demarrage" ("{0:N1} Go" -f ($st.SentBytes / 1GB)) }
      }
      $titreBarres = 'Programmes (disque + reseau)'
      $top = @(Top-Processus 'IODataBytesPersec' 6); $m = if ($top.Count) { [math]::Max(1, $top[0].v) } else { 1 }
      foreach ($p in $top) { $barres += Barre $p.nom ($p.v / $m) ("{0:N0} Ko/s" -f ($p.v / 1KB)) }
    }
    'fps' {
      $lignes += L 'Jeu' $(if ($Perf.jeu) { $Perf.jeu } else { 'aucun' })
      $lignes += L 'Images / s' $Perf.fps
      if ($Perf.fps -gt 0) { $lignes += L 'Temps par image' ("{0:N1} ms" -f (1000 / $Perf.fps)) }
      $lignes += L 'Carte graphique' "$($Perf.gpu) %"
      $lignes += L 'Processeur' "$($Perf.cpu) %"
      if ($null -ne $Perf.gpuTemp) { $lignes += L 'Temp. carte graphique' "$($Perf.gpuTemp) °C" }
    }
  }
  return [ordered]@{ lignes = @($lignes); titreBarres = $titreBarres; barres = @($barres) }
}

# ---------- Profils Chrome ----------
$ChromeDonnees = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
function Chemin-Chrome {
  $p = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe' -ErrorAction SilentlyContinue).'(default)'
  if (-not $p) { $p = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe" }
  return $p
}
function Profils-Chrome {
  $etat = Get-Content (Join-Path $ChromeDonnees 'Local State') -Raw -Encoding UTF8 | ConvertFrom-Json
  $etat.profile.info_cache.PSObject.Properties | ForEach-Object {
    [ordered]@{
      dossier = $_.Name
      nom     = $_.Value.name
      compte  = $_.Value.gaia_name
      photo   = Test-Path (Join-Path $ChromeDonnees "$($_.Name)\Google Profile Picture.png")
    }
  } | Sort-Object { $_.nom }
}

# ---------- Actions ----------
function Executer($b) {
  switch ($b.type) {
    'app'     { Start-Process -FilePath $b.cible }
    'touches' { Envoyer-Touches $b.cible }
  }
}

# ---------- HTTP ----------
function Repondre($ctx, [int]$code, [string]$type, [byte[]]$data) {
  $r = $ctx.Response
  $r.StatusCode = $code; $r.ContentType = $type; $r.ContentLength64 = $data.Length
  $r.OutputStream.Write($data, 0, $data.Length); $r.Close()
}
function Texte($ctx, [int]$code, [string]$t, [string]$type = 'text/plain; charset=utf-8') {
  Repondre $ctx $code $type ([Text.Encoding]::UTF8.GetBytes($t))
}

# ---------- Cable USB (fil a part) ----------
# Surveille le telephone toutes les 3 s et repare tout seul : adb bloque,
# telephone "offline", renvoi du port perdu apres un debranchement.
# Chaque commande adb a une limite de temps : un adb bloque ne fige plus le serveur.
$codeCable = {
  param($Perf, $Adb, $Port)
  function Lancer-Adb([string]$arguments, [int]$ms = 5000) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo($Adb, $arguments)
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $sortie = $p.StandardOutput.ReadToEndAsync()
    [void]$p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($ms)) { try { $p.Kill() } catch {}; return $null }
    return $sortie.Result
  }
  function Relancer-Adb {
    Get-Process adb -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    [void](Lancer-Adb 'start-server' 10000)
  }
  $horsLigneDepuis = $null; $absentDepuis = $null; $derniereRelance = [datetime]::MinValue
  $aDeck = @{}   # numero de telephone -> l'app Deck y est-elle installee ?
  while ($true) {
    try {
      $liste = Lancer-Adb 'devices'
      if ($null -eq $liste) {
        $Perf.cable = 'adb bloque : relance'
        Relancer-Adb; $derniereRelance = Get-Date
      } else {
        # Plusieurs telephones peuvent etre branches : on vise chacun par son numero (-s),
        # et on ne branche le renvoi que sur ceux ou l'app Deck est installee.
        $appareils = @($liste -split "`n" | Where-Object { $_ -match '^\S+\s+(device|offline|unauthorized)' } |
          ForEach-Object { $c = $_.Trim() -split '\s+'; [pscustomobject]@{ serie = $c[0]; etat = $c[1] } })
        $avecDeck = @()
        foreach ($a in @($appareils | Where-Object etat -eq 'device')) {
          if (-not $aDeck.ContainsKey($a.serie)) {
            $pk = Lancer-Adb "-s $($a.serie) shell pm list packages com.myblackwhite.deck"
            if ($null -ne $pk) { $aDeck[$a.serie] = ($pk -match 'com.myblackwhite.deck') }
          }
          if ($aDeck[$a.serie]) { $avecDeck += $a.serie }
        }
        $etat = if ($avecDeck.Count -gt 0) { 'device' }
                elseif (@($appareils | Where-Object etat -eq 'offline').Count -gt 0) { 'offline' }
                else { 'absent' }
        $Perf.cable = "$etat " + (($appareils | ForEach-Object { "$($_.serie)=$($_.etat)" }) -join ',')
        switch ($etat) {
          'device' {
            $horsLigneDepuis = $null; $absentDepuis = $null
            foreach ($serie in $avecDeck) {
              $renvois = Lancer-Adb "-s $serie reverse --list"
              if ($renvois -notmatch "tcp:$Port") { [void](Lancer-Adb "-s $serie reverse tcp:$Port tcp:$Port") }
            }
          }
          'offline' {
            if (-not $horsLigneDepuis) { $horsLigneDepuis = Get-Date }
            if (((Get-Date) - $horsLigneDepuis).TotalSeconds -gt 4) {
              [void](Lancer-Adb 'reconnect offline'); $horsLigneDepuis = Get-Date
            }
          }
          'absent' {
            # Le telephone est branche (vu par Windows) mais adb ne le voit pas : on relance adb,
            # au plus une fois par minute.
            $branche = @(Get-PnpDevice -PresentOnly -Class AndroidUsbDeviceClass -ErrorAction SilentlyContinue).Count -gt 0
            if ($branche) {
              if (-not $absentDepuis) { $absentDepuis = Get-Date }
              if (((Get-Date) - $absentDepuis).TotalSeconds -gt 8 -and ((Get-Date) - $derniereRelance).TotalSeconds -gt 30) {
                $Perf.cable = 'branche mais invisible : relance adb'
                Relancer-Adb; $derniereRelance = Get-Date; $absentDepuis = $null
              }
            } else { $absentDepuis = $null }
          }
        }
      }
    } catch { $Perf.cable = "erreur : $_" }
    # Telephone pas encore la : on regarde chaque seconde pour le brancher des qu'il arrive.
    if ($Perf.cable -like 'device*') { Start-Sleep -Seconds 3 } else { Start-Sleep -Milliseconds 1000 }
  }
}

# ---------- Performances (dans des fils a part) ----------
# Chaque fil range ses mesures dans $Perf ; /perfs les assemble a la demande.
$Perf = [hashtable]::Synchronized(@{})
$PresentMon = 'C:\Program Files\AMD\CNext\CNext\PresentMon-x64.exe'

# Code compile (rapide) : lecture de PresentMon et fenetre au premier plan.
# PresentMon liste chaque image affichee ; on garde, pour chaque fenetre de rendu
# (processus + "swapchain"), les ecarts entre images de la derniere seconde.
Add-Type @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;

public static class DeckFenetre {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public static int PremierPlan() {
    uint pid; GetWindowThreadProcessId(GetForegroundWindow(), out pid); return (int)pid;
  }
}

public static class DeckFps {
  struct Image { public double T; public double Ms; }
  static readonly object Verrou = new object();
  static readonly Dictionary<string, Queue<Image>> Chaines = new Dictionary<string, Queue<Image>>();
  static readonly Dictionary<string, double> Derniere = new Dictionary<string, double>();
  static double TMax = 0;
  static Process P;
  public static int Lignes = 0;
  public static int PresentMonPid { get { return P == null ? 0 : P.Id; } }

  static string Exe;
  static DateTime DerniereLigne = DateTime.Now;
  public static int Relances = 0;

  // Relance PresentMon s'il est mort ou muet depuis 20 s.
  public static void Verifier() {
    if (Exe == null) return;
    bool mort = true;
    try { mort = P == null || P.HasExited; } catch { }
    if (mort || (DateTime.Now - DerniereLigne).TotalSeconds > 20) {
      Arreter();
      Relances++;
      Demarrer(Exe);
    }
  }

  public static void Demarrer(string exe) {
    Exe = exe;
    DerniereLigne = DateTime.Now;
    var psi = new ProcessStartInfo(exe, "-stop_existing_session -output_stdout -session_name DeckFps");
    psi.UseShellExecute = false;
    psi.RedirectStandardOutput = true;
    psi.CreateNoWindow = true;
    P = new Process();
    P.StartInfo = psi;
    P.OutputDataReceived += (s, e) => { if (e.Data != null) Lire(e.Data); };
    P.Start();
    P.BeginOutputReadLine();
  }

  public static void Arreter() {
    try { if (P != null && !P.HasExited) P.Kill(); } catch { }
  }

  static void Lire(string l) {
    DerniereLigne = DateTime.Now;
    var c = l.Split(',');
    if (c.Length < 10 || c[1] == "ProcessID") return;
    int pid; double t, ms;
    if (!int.TryParse(c[1], out pid)) return;
    if (!double.TryParse(c[7], NumberStyles.Float, CultureInfo.InvariantCulture, out t)) return;
    if (!double.TryParse(c[9], NumberStyles.Float, CultureInfo.InvariantCulture, out ms)) return;
    string cle = pid + "|" + c[2];
    lock (Verrou) {
      Lignes++;
      Queue<Image> q;
      if (!Chaines.TryGetValue(cle, out q)) { q = new Queue<Image>(); Chaines[cle] = q; }
      q.Enqueue(new Image { T = t, Ms = ms });
      while (q.Count > 0 && q.Peek().T < t - 1.0) q.Dequeue();
      Derniere[cle] = t;
      if (t > TMax) TMax = t;
    }
  }

  // FPS d'un processus : sa fenetre de rendu la plus active,
  // 1000 / moyenne des ms entre images sur la derniere seconde.
  public static double Fps(int pid) {
    lock (Verrou) {
      double meilleur = 0; int nMax = 0;
      var morts = new List<string>();
      string debut = pid + "|";
      foreach (var kv in Chaines) {
        double d = Derniere[kv.Key];
        if (TMax - d > 10) { morts.Add(kv.Key); continue; }
        if (!kv.Key.StartsWith(debut) || TMax - d > 0.5) continue;
        double somme = 0; int n = 0;
        foreach (var im in kv.Value) if (im.T >= TMax - 1.0) { somme += im.Ms; n++; }
        if (n >= 2 && somme > 0 && n > nMax) { nMax = n; meilleur = 1000.0 * n / somme; }
      }
      foreach (var k in morts) { Chaines.Remove(k); Derniere.Remove(k); }
      return meilleur;
    }
  }

  public static int[] Pids() {
    lock (Verrou) {
      var s = new HashSet<int>();
      foreach (var k in Chaines.Keys) s.Add(int.Parse(k.Split('|')[0]));
      var a = new int[s.Count]; s.CopyTo(a); return a;
    }
  }
}
"@

# Fil rapide (toutes les 0,5 s) : FPS du jeu au premier plan et debit internet.
$codeRapide = {
  param($Perf)
  $infos = @{}   # pid -> @(nom, parent, description)
  function Info([int]$id) {
    if (-not $infos.ContainsKey($id)) {
      $w = Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
      $pr = Get-Process -Id $id -ErrorAction SilentlyContinue
      $desc = if ($pr.Description) { $pr.Description } elseif ($pr) { $pr.ProcessName } else { $null }
      $infos[$id] = @($w.Name, $w.ParentProcessId, $desc)
      if ($infos.Count -gt 500) { $infos.Clear() }
    }
    return $infos[$id]
  }
  # Seulement les vraies cartes reseau (pas Tailscale ni les cartes virtuelles).
  $physiques = @(); $prochaineCartes = Get-Date
  $echantillons = New-Object System.Collections.Generic.Queue[object]
  $gardeJeu = $null; $gardeFps = 0; $gardeJusqua = Get-Date

  while ($true) {
    try {
      $maintenant = Get-Date
      # --- FPS ---
      [DeckFps]::Verifier()
      $fg =[DeckFenetre]::PremierPlan()
      $fps = [DeckFps]::Fps($fg)
      if ($fps -le 0 -and $fg -gt 0) {
        # Le rendu peut venir d'un autre processus (meme nom, ou enfant de la fenetre).
        $nomFg = (Info $fg)[0]
        foreach ($id in [DeckFps]::Pids()) {
          if ($id -eq $fg) { continue }
          $inf = Info $id
          if ($inf[0] -eq $nomFg -or $inf[1] -eq $fg) { $fps = [math]::Max($fps, [DeckFps]::Fps($id)) }
        }
      }
      $jeu = if ($fps -gt 0) { (Info $fg)[2] } else { $null }
      if ($fps -gt 0) {
        $gardeFps = if ($gardeJeu -eq $jeu -and $gardeFps -gt 0) { 0.5 * $gardeFps + 0.5 * $fps } else { $fps }
        $gardeJeu = $jeu; $gardeJusqua = $maintenant.AddSeconds(2)
      } elseif ($maintenant -gt $gardeJusqua) {
        # Plus aucune image depuis 2 s : on est vraiment hors jeu.
        $gardeFps = 0; $gardeJeu = $null
      }
      $Perf.fps = [int][math]::Round($gardeFps)
      $Perf.jeu = $gardeJeu

      # --- Debit internet : octets cumules, debit calcule sur 3 s ---
      if ($maintenant -gt $prochaineCartes) {
        $physiques = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | ForEach-Object InterfaceDescription)
        $prochaineCartes = $maintenant.AddMinutes(1)
      }
      $recu = 0L; $envoye = 0L
      foreach ($ni in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($physiques -contains $ni.Description) {
          $st = $ni.GetIPStatistics()
          $recu += $st.BytesReceived; $envoye += $st.BytesSent
        }
      }
      $echantillons.Enqueue(@($maintenant, $recu, $envoye))
      while ($echantillons.Count -gt 2 -and ($maintenant - $echantillons.Peek()[0]).TotalSeconds -gt 3) { [void]$echantillons.Dequeue() }
      $premier = $echantillons.Peek()
      $dt = ($maintenant - $premier[0]).TotalSeconds
      if ($dt -gt 0.4) {
        $Perf.netIn  = [math]::Round(($recu - $premier[1]) / 1KB / $dt, 0)
        $Perf.netOut = [math]::Round(($envoye - $premier[2]) / 1KB / $dt, 0)
      }
    } catch { $Perf.erreurRapide = "$_" }
    Start-Sleep -Milliseconds 500
  }
}

# Fil lent (~1,5 s) : processeur, carte graphique, memoire, temperatures.
$codeLent = {
  param($Perf)
  $ramTotal = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
  $vramTotal = (Get-ItemProperty 'HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0*' -ErrorAction SilentlyContinue |
    ForEach-Object { $_.'HardwareInformation.qwMemorySize' } | Measure-Object -Maximum).Maximum / 1GB
  $Perf.ramTotal = [math]::Round($ramTotal, 0)
  $Perf.vramTotal = [math]::Round($vramTotal, 0)
  while ($true) {
    try {
      $cpu  = (Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'").PercentProcessorUtility
      $gpu  = (Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine |
                Where-Object Name -like '*engtype_3D' | Measure-Object UtilizationPercentage -Sum).Sum
      $vram = (Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory | Measure-Object DedicatedUsage -Sum).Sum / 1GB
      $mem  = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory).AvailableMBytes / 1024
      $Perf.cpu  = [math]::Min(100, [math]::Round([double]$cpu, 0))
      $Perf.gpu  = [math]::Min(100, [math]::Round([double]$gpu, 0))
      $Perf.vram = [math]::Round($vram, 1)
      $Perf.ram  = [math]::Round($ramTotal - $mem, 1)

      # Temperatures : lues dans LibreHardwareMonitor (serveur web sur le port 8085).
      $tCpu = $null; $tGpu = $null
      try {
        $lhm = Invoke-RestMethod 'http://localhost:8085/data.json' -TimeoutSec 1 -UseBasicParsing
        $pile = New-Object System.Collections.Stack
        $pile.Push($lhm)
        while ($pile.Count -gt 0) {
          $n = $pile.Pop()
          foreach ($c in @($n.Children)) { if ($c) { $pile.Push($c) } }
          if ($n.Type -ne 'Temperature' -or -not $n.SensorId) { continue }
          $txt = [regex]::Match([string]$n.Value, '-?\d+([.,]\d+)?').Value -replace ',', '.'
          if (-not $txt) { continue }
          $v = [math]::Round([double]::Parse($txt, [Globalization.CultureInfo]::InvariantCulture), 0)
          if ($n.SensorId -like '/*cpu/*' -and $n.Text -match 'Tctl|CPU Package') { $tCpu = $v }
          if ($n.SensorId -like '/gpu*' -and $n.Text -eq 'GPU Core') { $tGpu = $v }
        }
      } catch {}
      $Perf.cpuTemp = $tCpu
      $Perf.gpuTemp = $tGpu
    } catch { $Perf.erreurLent = "$_" }
    Start-Sleep -Milliseconds 250
  }
}

# Fil du ping (toutes les 2 s) : temps de reponse d'internet, moyenne des 3 derniers.
$codePing = {
  param($Perf)
  $pinger = New-Object System.Net.NetworkInformation.Ping
  $derniers = New-Object System.Collections.Generic.Queue[int]
  while ($true) {
    try {
      $r = $pinger.Send('1.1.1.1', 1500)
      if ($r.Status -eq 'Success') {
        $derniers.Enqueue([int]$r.RoundtripTime)
        while ($derniers.Count -gt 3) { [void]$derniers.Dequeue() }
        $Perf.ping = [int][math]::Round(($derniers | Measure-Object -Average).Average)
      } else { $Perf.ping = -1; $derniers.Clear() }
    } catch { $Perf.ping = -1 }
    Start-Sleep -Seconds 2
  }
}

# Fil des apps ouvertes (toutes les 2 s) : pour chaque bouton, le dossier ou son app est installee ;
# un programme qui tourne depuis ce dossier = l'app est ouverte. $Perf.actifs : id -> pids.
$codeActifs = {
  param($Perf, $Config)
  $racines = @{}; $noms = @{}; $date = [datetime]::MinValue
  $sh = New-Object -ComObject WScript.Shell
  function Racine([string]$chemin) {
    if (-not $chemin) { return $null }
    $chemin = $chemin -replace '/', '\'
    $chemin = $chemin.Replace('{6D809377-6AF0-444B-8957-A3773F02200E}', $env:ProgramFiles).Replace('{7C5A40EF-A0FB-4BFC-874A-C0F2E0B9FA8E}', ${env:ProgramFiles(x86)})
    if ($chemin -match '^(.*\\(Epic Games|steamapps\\common|Riot Games)\\[^\\]+)') { return $Matches[1] }
    if ($chemin -match '\\Windows\\|^[A-Z]:\\[^\\]*$') { return $null }
    $d = Split-Path $chemin
    if ($d -match '^[A-Z]:\\(Program Files( \(x86\))?)?$') { return $null }
    return $d
  }
  function Preparer($b) {
    $s = [string]$b.cible
    if ($b.processus) { return @{ nom = [string]$b.processus } }
    if ($s -like '*.lnk') {
      $l = $sh.CreateShortcut($s)
      if ($l.TargetPath -match 'chrome(_proxy)?\.exe$') { return $null }   # appli web Chrome : pas de fermeture
      if ($l.Arguments -match '--launch-product=(\w+)') { return @{ dossier = Join-Path (Split-Path (Split-Path $l.TargetPath)) $Matches[1] } }
      $r = Racine $l.TargetPath
      if ($r) { return @{ dossier = $r } }
      return @{ nom = [IO.Path]::GetFileNameWithoutExtension($l.TargetPath) -replace '^i386_', '' }
    }
    if ($s -like '*.url') {
      $u = Get-Content $s
      $url = ($u | Where-Object { $_ -like 'URL=*' } | Select-Object -First 1)
      if ($url -match 'steam://rungameid/(\d+)') {
        $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath -replace '/', '\'
        $vdf = Get-Content "$steam\steamapps\libraryfolders.vdf" -Raw -ErrorAction SilentlyContinue
        foreach ($lib in [regex]::Matches([string]$vdf, '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' }) {
          $acf = "$lib\steamapps\appmanifest_$($Matches[1]).acf"
          if (Test-Path $acf) { $dir = [regex]::Match((Get-Content $acf -Raw), '"installdir"\s+"([^"]+)"').Groups[1].Value; return @{ dossier = "$lib\steamapps\common\$dir" } }
        }
        return $null
      }
      $ico = ($u | Where-Object { $_ -like 'IconFile=*' } | Select-Object -First 1)
      if ($ico -and $ico.Substring(9) -like '*.exe') { $r = Racine $ico.Substring(9); if ($r) { return @{ dossier = $r } } }
      return $null
    }
    if ($s -like 'shell:AppsFolder\*') {
      $id = $s.Substring(17)
      if ($id -match '\\') { $r = Racine $id; if ($r) { return @{ dossier = $r } }; return $null }
      $famille = ($id -split '!')[0]
      $pk = Get-AppxPackage | Where-Object PackageFamilyName -eq $famille | Select-Object -First 1
      if ($pk) { return @{ dossier = $pk.InstallLocation } }
    }
    return $null
  }
  while ($true) {
    try {
      $d = (Get-Item $Config).LastWriteTimeUtc
      if ($d -ne $date) {
        $racines = @{}
        foreach ($b in (Get-Content $Config -Raw -Encoding UTF8 | ConvertFrom-Json).boutons | Where-Object type -eq 'app') {
          try { $p = Preparer $b; if ($p) { $racines[$b.id] = $p } } catch {}
        }
        $date = $d
      }
      $procs = @(Get-CimInstance Win32_Process -Property ProcessId, Name, ExecutablePath -ErrorAction SilentlyContinue)
      $actifs = @{}
      foreach ($id in $racines.Keys) {
        $r = $racines[$id]
        $pids = if ($r.dossier) {
          $pref = $r.dossier.TrimEnd('\') + '\'
          $avecSteam = $pref -like '*\steamapps\*'
          @($procs | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($pref, [StringComparison]::OrdinalIgnoreCase) -and ($avecSteam -or $_.ExecutablePath -notlike '*\steamapps\*') } | ForEach-Object { [int]$_.ProcessId })
        } else {
          @($procs | Where-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $r.nom } | ForEach-Object { [int]$_.ProcessId })
        }
        if ($pids.Count) { $actifs[$id] = $pids }
      }
      $Perf.actifs = $actifs
    } catch { $Perf.erreurActifs = "$_" }
    Start-Sleep -Seconds 2
  }
}

# Fil des appuis : son propre ecouteur sur /appui/, pour qu'un appui ne fasse jamais
# la queue derriere une autre demande (icones, details...). Lancement direct, sans PowerShell.
$codeAppui = {
  param($Config, $Port, $NomsTouches, $Etendues, $Perf)
  $Journal = Join-Path (Split-Path $Config) 'deck-appuis.log'
  $cache = $null; $date = [datetime]::MinValue
  function Boutons {
    $d = (Get-Item $Config).LastWriteTimeUtc
    if ($d -ne $script:date -or -not $script:cache) {
      $script:cache = @{}
      foreach ($b in (Get-Content $Config -Raw -Encoding UTF8 | ConvertFrom-Json).boutons) { $script:cache[$b.id] = $b }
      $script:date = $d
    }
    return $script:cache
  }
  function Touches([string]$combo) {
    $codes = @($combo.Split('+') | ForEach-Object {
      $n = $_.Trim().ToUpper()
      if ($NomsTouches.ContainsKey($n)) { [byte]$NomsTouches[$n] } elseif ($n.Length -eq 1) { [byte][char]$n }
    })
    foreach ($c in $codes) { [DeckClavier]::keybd_event($c, 0, $(if ($Etendues -contains $c) { 1 } else { 0 }), [UIntPtr]::Zero) }
    [array]::Reverse($codes)
    foreach ($c in $codes) { [DeckClavier]::keybd_event($c, 0, $(if ($Etendues -contains $c) { 3 } else { 2 }), [UIntPtr]::Zero) }
  }
  $ecoute = New-Object System.Net.HttpListener
  $ecoute.Prefixes.Add("http://localhost:$Port/appui/")
  $ecoute.Start()
  [void](Boutons)
  while ($true) {
    $ctx = $ecoute.GetContext()
    $b = $null
    try { $b = (Boutons)[$ctx.Request.Url.AbsolutePath.Trim('/').Substring(6)] } catch { $script:erreurAppui = "$_" }
    try { Add-Content $Journal "$(Get-Date -Format 'HH:mm:ss.fff') $($ctx.Request.HttpMethod) $($ctx.Request.Url.AbsolutePath) -> $($b.nom) $script:erreurAppui" } catch {}
    # On repond tout de suite au telephone, puis on lance.
    try { $ctx.Response.StatusCode = $(if ($b) { 200 } else { 404 }); $ctx.Response.ContentLength64 = 0; $ctx.Response.Close() } catch {}
    try {
      if ($b.type -eq 'touches') { Touches $b.cible }
      elseif ($b.type -eq 'app') {
        # Deja ouverte : on la ferme. Sinon on la lance.
        $ouverts = $null
        if ($Perf.actifs) { $ouverts = $Perf.actifs[$b.id] }
        if ($ouverts) {
          [DeckFerme]::Fermer([int[]]$ouverts)
          $copie = @{} + $Perf.actifs; $copie.Remove($b.id); $Perf.actifs = $copie
          try { Add-Content $Journal "  fermeture : $($ouverts -join ',')" } catch {}
        } else { [DeckLance]::Lancer([string]$b.cible) }
      }
    } catch { try { Add-Content $Journal "  erreur lancement : $_" } catch {} }
  }
}

function Json-Perfs {
  if ($null -eq $Perf.cpu) { return '{}' }
  [ordered]@{
    cpu = $Perf.cpu; gpu = $Perf.gpu; cpuTemp = $Perf.cpuTemp; gpuTemp = $Perf.gpuTemp
    ram = $Perf.ram; ramTotal = $Perf.ramTotal; vram = $Perf.vram; vramTotal = $Perf.vramTotal
    netIn = [int]$Perf.netIn; netOut = [int]$Perf.netOut; ping = $Perf.ping; actifs = @($(if ($Perf.actifs) { $Perf.actifs.Keys }))
    fps = [int]$Perf.fps; jeu = $Perf.jeu
  } | ConvertTo-Json -Compress
}

function Lancer-Fil($code, [object[]]$arguments) {
  $ps = [PowerShell]::Create()
  [void]$ps.AddScript($code)
  foreach ($a in $arguments) { [void]$ps.AddArgument($a) }
  [void]$ps.BeginInvoke()
  return $ps
}
if (Test-Path $PresentMon) { [DeckFps]::Demarrer($PresentMon) }
$filRapide = Lancer-Fil $codeRapide @($Perf)
$filLent = Lancer-Fil $codeLent @($Perf)
$filCable = Lancer-Fil $codeCable @($Perf, $Adb, $Port)
$filPing = Lancer-Fil $codePing @($Perf)
$filAppui = Lancer-Fil $codeAppui @($Config, $Port, $NomsTouches, $Etendues, $Perf)
$filActifs = Lancer-Fil $codeActifs @($Perf, $Config)

[void](Lire-Config)
$http = New-Object System.Net.HttpListener
$http.Prefixes.Add("http://localhost:$Port/")
$http.Start()
Write-Host "Deck : serveur pret sur le port $Port. Ctrl+C pour arreter."

try {
while ($http.IsListening) {
  $ctx = $http.GetContext()
  try {
    $chemin = $ctx.Request.Url.AbsolutePath.Trim('/')
    $cfg = Lire-Config
    if ($chemin -eq 'ping') {
      Texte $ctx 200 (Version-Config)
    } elseif ($chemin -eq 'perfs') {
      Texte $ctx 200 (Json-Perfs) 'application/json; charset=utf-8'
    } elseif ($chemin -eq 'chrome/profils') {
      $json = ConvertTo-Json -InputObject @(Profils-Chrome) -Depth 3 -Compress
      Texte $ctx 200 $json 'application/json; charset=utf-8'
    } elseif ($chemin -like 'chrome/photo/*') {
      $dossier = [Uri]::UnescapeDataString($chemin.Substring(13))
      $png = Join-Path $ChromeDonnees "$dossier\Google Profile Picture.png"
      if ($dossier -notmatch '[\\/]|\.\.' -and (Test-Path $png)) { Repondre $ctx 200 'image/png' ([IO.File]::ReadAllBytes($png)) }
      else { Texte $ctx 404 'pas de photo' }
    } elseif ($chemin -like 'chrome/ouvrir/*' -and $ctx.Request.HttpMethod -eq 'POST') {
      $dossier = [Uri]::UnescapeDataString($chemin.Substring(14))
      if (@(Profils-Chrome | Where-Object { $_.dossier -eq $dossier }).Count -eq 1) {
        Start-Process -FilePath (Chemin-Chrome) -ArgumentList "--profile-directory=`"$dossier`""
        Write-Host "Chrome : profil $dossier"
        Texte $ctx 200 'ok'
      } else { Texte $ctx 404 'profil inconnu' }
    } elseif ($chemin -eq 'fps') {
      # Diagnostic : images par seconde de chaque programme vu par PresentMon.
      $lignes = @([DeckFps]::Pids() | ForEach-Object {
        "{0} {1} fps={2:N1}" -f $_, (Get-Process -Id $_ -ErrorAction SilentlyContinue).ProcessName, [DeckFps]::Fps($_)
      })
      $fin = "icone=$script:ErreurIcone`ncable=$($Perf.cable) lignes=$([DeckFps]::Lignes) relances=$([DeckFps]::Relances) pm=$([DeckFps]::PresentMonPid) premier-plan=$([DeckFenetre]::PremierPlan()) erreurs=$($Perf.erreurRapide) $($Perf.erreurLent) actifs=$($Perf.erreurActifs) n=$(if ($Perf.actifs) { $Perf.actifs.Count } else { 'null' })"
      Texte $ctx 200 (($lignes + $fin) -join "`n")
    } elseif ($chemin -eq 'boutons') {
      $liste = @($cfg.boutons | ForEach-Object {
        [ordered]@{ id=$_.id; nom=$_.nom; type=$_.type; groupe=$_.groupe; couleur=$_.couleur; icone=[bool](Icone-Png $_) }
      })
      $json = [ordered]@{ version=(Version-Config); colonnes=$cfg.colonnes; groupes=@($cfg.groupes); boutons=$liste } | ConvertTo-Json -Depth 4 -Compress
      Texte $ctx 200 $json 'application/json; charset=utf-8'
    } elseif ($chemin -like 'icone/*') {
      $b = $cfg.boutons | Where-Object { $_.id -eq $chemin.Substring(6) } | Select-Object -First 1
      $png = if ($b) { Icone-Png $b }
      if ($png) { Repondre $ctx 200 'image/png' ([IO.File]::ReadAllBytes($png)) } else { Texte $ctx 404 'pas d icone' }
    } elseif ($chemin -like 'details/*') {
      $json = Details $chemin.Substring(8) | ConvertTo-Json -Depth 5 -Compress
      Texte $ctx 200 $json 'application/json; charset=utf-8'
    } elseif ($chemin -eq 'composants') {
      Texte $ctx 200 (Composants | ConvertTo-Json -Depth 6 -Compress) 'application/json; charset=utf-8'
    } elseif ($chemin -eq 'apps') {
      # Toutes les apps du PC, avec celles deja sur le Deck marquees.
      # Une app est "sur le Deck" si un bouton a la meme cible ou le meme nom.
      $cibles = @{}; $noms = @{}; $pris = @{}
      foreach ($b in $cfg.boutons) {
        if ($b.cible) { $cibles[([string]$b.cible).ToLower()] = $b.id }
        $noms[([string]$b.nom).ToLower()] = $b.id
      }
      $liste = @(Apps-Pc | Sort-Object { $_.nom } | ForEach-Object {
        $id = $cibles[$_.cible.ToLower()]
        if (-not $id) { $id = $noms[$_.nom.ToLower()] }
        if ($id) { $pris[$id] = 1 }
        [ordered]@{ cle = (Cle-Texte $_.cible); nom = $_.nom; bouton = $id }
      })
      # Les boutons du Deck qui ne sont pas des apps (raccourcis clavier, Chrome...) : on peut les retirer aussi.
      $autres = @($cfg.boutons | Where-Object { -not $pris.ContainsKey($_.id) } | ForEach-Object {
        [ordered]@{ cle = "deck-$($_.id)"; nom = $_.nom; bouton = $_.id }
      })
      # D'abord ce qui est deja sur le Deck, puis le reste.
      $liste = @($autres) + @($liste | Where-Object { $_.bouton }) + @($liste | Where-Object { -not $_.bouton })
      Texte $ctx 200 (ConvertTo-Json -InputObject $liste -Depth 3 -Compress) 'application/json; charset=utf-8'
    } elseif ($chemin -like 'apps/icone/*') {
      $cle = $chemin.Substring(11)
      if ($script:AppsPc.Count -eq 0) { [void](Apps-Pc) }
      $a = $script:AppsPc[$cle]
      $png = if ($cle -like 'deck-*') {
        $b = $cfg.boutons | Where-Object { $_.id -eq $cle.Substring(5) } | Select-Object -First 1
        if ($b) { Icone-Png $b }
      } elseif ($a -and $cle -match '^[0-9a-f]+$') { Icone-Fichier $a.cible (Join-Path $IconesApps "$cle.png") $a.nom }
      if ($png) { Repondre $ctx 200 'image/png' ([IO.File]::ReadAllBytes($png)) } else { Texte $ctx 404 'pas d icone' }
    } elseif ($chemin -like 'ajouter/*' -and $ctx.Request.HttpMethod -eq 'POST') {
      if ($script:AppsPc.Count -eq 0) { [void](Apps-Pc) }
      $a = $script:AppsPc[$chemin.Substring(8)]
      if ($a) {
        $num = ($cfg.boutons | ForEach-Object { [int]($_.id -replace '\D', '') } | Measure-Object -Maximum).Maximum + 1
        $groupe = $ctx.Request.QueryString['groupe']
        $nouveau = [pscustomobject][ordered]@{ id = "b$num"; nom = $a.nom; type = 'app'; cible = $a.cible; groupe = $groupe }
        $cfg.boutons = @($cfg.boutons) + $nouveau
        Sauver-Config $cfg
        Write-Host "Ajoute : $($a.nom)"
        Texte $ctx 200 "b$num"
      } else { Texte $ctx 404 'app inconnue' }
    } elseif ($chemin -eq 'ordre' -and $ctx.Request.HttpMethod -eq 'POST') {
      # Nouvel ordre d'une categorie : ces boutons reprennent les memes places, dans le nouvel ordre.
      $ids = @(([string]$ctx.Request.QueryString['ids']).Split(',') | Where-Object { $_ })
      $liste = @($cfg.boutons)
      $places = @(for ($i = 0; $i -lt $liste.Count; $i++) { if ($ids -contains $liste[$i].id) { $i } })
      if ($places.Count -eq $ids.Count -and $ids.Count -gt 0) {
        $parId = @{}; foreach ($b in $liste) { $parId[$b.id] = $b }
        for ($k = 0; $k -lt $places.Count; $k++) { $liste[$places[$k]] = $parId[$ids[$k]] }
        $cfg.boutons = $liste
        Sauver-Config $cfg
        Texte $ctx 200 'ok'
      } else { Texte $ctx 400 'ordre invalide' }
    } elseif ($chemin -like 'retirer/*' -and $ctx.Request.HttpMethod -eq 'POST') {
      $id = $chemin.Substring(8)
      if (@($cfg.boutons | Where-Object id -eq $id).Count -eq 1) {
        $cfg.boutons = @($cfg.boutons | Where-Object id -ne $id)
        Sauver-Config $cfg
        Remove-Item (Join-Path $Icones "$id.png") -ErrorAction SilentlyContinue
        Write-Host "Retire : $id"
        Texte $ctx 200 'ok'
      } else { Texte $ctx 404 'bouton inconnu' }
    } elseif ($chemin -like 'appui/*' -and $ctx.Request.HttpMethod -eq 'POST') {
      $b = $cfg.boutons | Where-Object { $_.id -eq $chemin.Substring(6) } | Select-Object -First 1
      if ($b) { Executer $b; Write-Host "Appui : $($b.nom)"; Texte $ctx 200 'ok' } else { Texte $ctx 404 'bouton inconnu' }
    } else {
      Texte $ctx 404 'inconnu'
    }
  } catch {
    Write-Host "Erreur : $_"
    try { Texte $ctx 500 "$_" } catch {}
  }
}
} finally {
  # A l'arret du serveur, on arrete aussi PresentMon.
  [DeckFps]::Arreter()
  # Tuer PresentMon laisse sa session de mesure ouverte : on la ferme aussi.
  logman stop DeckFps -ets 2>$null | Out-Null
}
