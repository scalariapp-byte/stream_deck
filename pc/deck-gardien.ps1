# Gardien du serveur Deck : le relance tout seul s'il s'arrete (plantage, coupure...).
# C'est ce script que lance le demarrage de Windows.
$serveur = Join-Path $PSScriptRoot 'deck-serveur.ps1'
$ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

# Un seul gardien a la fois.
$verrou = New-Object System.Threading.Mutex($false, 'Local\DeckGardien')
if (-not $verrou.WaitOne(0)) { exit }

$journal = Join-Path $PSScriptRoot 'deck-gardien.log'
function Noter($t) { Add-Content $journal "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $t" }
Noter 'gardien demarre'

while ($true) {
  try {
    $p = Start-Process $ps -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$serveur`"" -WindowStyle Hidden -PassThru
    Noter "serveur lance (pid $($p.Id))"
    $p.WaitForExit()
    Noter "serveur arrete (code $($p.ExitCode))"
  } catch { Noter "erreur : $_" }
  # Petite pause pour ne pas boucler trop vite si le serveur plante au demarrage.
  Start-Sleep -Seconds 1
}
