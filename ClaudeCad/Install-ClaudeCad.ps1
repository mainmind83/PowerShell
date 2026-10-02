<#
.SYNOPSIS
    Claude + CAD: instala y configura el puente MCP entre Claude Desktop y FreeCAD.
    Claude + CAD: installs and configures the MCP bridge between Claude Desktop and FreeCAD.

.DESCRIPTION
    ES: Instalador idempotente y bilingüe (español/inglés). Ver README.md.
    EN: Idempotent, bilingual (Spanish/English) installer. See README.md.

.PARAMETER Lang
    es | en. Si no se indica, se detecta el idioma de Windows y se ofrece elegir.
    es | en. If omitted, the Windows language is detected and a choice is offered.

.PARAMETER WorkDir
    Directorio de trabajo / Working directory. Default: C:\mainmind\ClaudeCad

.PARAMETER FreeCADUserDir
    Fuerza la carpeta de usuario de FreeCAD / Forces the FreeCAD user folder
    (output of FreeCAD.getUserAppDataDir()).

.PARAMETER SkipClaudeConfig
    No toca la configuración de Claude Desktop / Does not touch Claude Desktop config.

.PARAMETER Feedback
    text  = solo texto (--only-text-feedback, menos tokens) / text only (fewer tokens)
    image = imágenes + texto / images + text.
    Si no se indica: se pregunta al crear la entrada y se respeta el modo existente después.
    If omitted: asked when the entry is created; the existing mode is kept afterwards.

.PARAMETER Force
    Rehace todos los pasos / Redoes every step.

.EXAMPLE
    .\Install-ClaudeCad.ps1
.EXAMPLE
    .\Install-ClaudeCad.ps1 -Lang en -Force
#>
[CmdletBinding()]
param(
    [ValidateSet('es', 'en')]
    [string]$Lang,
    [string]$WorkDir = 'C:\mainmind\ClaudeCad',
    [string]$FreeCADUserDir,
    [switch]$SkipClaudeConfig,
    [ValidateSet('text', 'image')]
    [string]$Feedback,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = '1.4.1'
$RepoUrl   = 'https://github.com/neka-nat/freecad-mcp.git'
$ZipUrl    = 'https://github.com/neka-nat/freecad-mcp/archive/refs/heads/main.zip'
$RepoDir   = Join-Path $WorkDir 'freecad-mcp'
$AddonName = 'FreeCADMCP'
$RpcPort   = 9875

# ---------------------------------------------------------------------------
# Textos / Strings
# ---------------------------------------------------------------------------
$Strings = @{
  es = @{
    Subtitle      = 'Instalador del puente MCP Claude Desktop <-> FreeCAD'
    ForceMode     = 'Modo -Force: se rehacen todos los pasos'
    Done          = 'Hecho'
    Skipped       = 'Omitido'
    S1            = '1. Directorio de trabajo: {0}'
    S1Name        = '1. Directorio de trabajo'
    Exists        = 'Ya existe'
    Existed       = 'Ya existía'
    Created       = 'Creado'
    S2            = '2. Repositorio neka-nat/freecad-mcp'
    S2Name        = '2. Repositorio'
    GitPullFail   = 'git pull falló en {0}'
    UpToDate      = 'Ya actualizado ({0})'
    UpToDateShort = 'Al día ({0})'
    Updated       = 'Actualizado {0} -> {1}'
    UpdatedTo     = 'Actualizado a {0}'
    ZipPresent    = 'Ya descargado (sin git no se puede comprobar si hay cambios; usa -Force para rehacer)'
    ZipPresentS   = 'Ya descargado (ZIP)'
    Cloned        = 'Clonado'
    CloneFail     = 'git clone falló'
    NoGit         = 'git no encontrado: se descarga como ZIP'
    ZipDone       = 'ZIP descargado y extraído'
    ZipDoneS      = 'Descargado (ZIP)'
    NoInitGui     = 'No se encuentra {0}\InitGui.py. ¿Ha cambiado la estructura del repositorio?'
    S3            = '3. uv'
    UvPresent     = 'Ya instalado: {0}'
    UvInstalling  = 'Instalando uv en {0}'
    UvFail        = 'La instalación de uv no dejó uvx.exe en {0}'
    UvDone        = 'Instalado: {0}'
    S4            = '4. Carpeta de usuario de FreeCAD'
    S4Name        = '4. Carpeta Mod'
    ParamPath     = 'Ruta indicada por parámetro: {0}'
    FcNotFound    = 'No se encuentra la carpeta de usuario de FreeCAD en {0}\FreeCAD\vX-Y'
    FcHint1       = 'FreeCAD la crea la primera vez que se abre tras instalarlo.'
    FcHint2       = 'Abre FreeCAD, espera a que cargue del todo y ciérralo.'
    FcAsk         = '¿Ya lo has abierto y cerrado al menos una vez? (S/N)'
    Yes           = 'S'
    No            = 'N'
    FcStopped     = 'Instalación detenida. Abre FreeCAD una vez y vuelve a ejecutar el script.'
    FcMissing     = 'La carpeta de usuario de FreeCAD no existe: {0}'
    FcUserDir     = 'Carpeta de usuario: {0}'
    ModExists     = 'Carpeta Mod ya existe: {0}'
    ModCreating   = 'La carpeta Mod no existe: se crea {0}'
    ModCreated    = 'Carpeta Mod creada'
    CreatedF      = 'Creada'
    ModFail       = 'No se pudo crear {0} : {1}'
    S5            = '5. Addon {0}'
    S5Name        = '5. Addon'
    AddonSame     = 'Ya instalado e idéntico al del repositorio: {0}'
    AddonSameS    = 'Ya instalado, sin cambios'
    AddonInst     = 'Instalado'
    AddonUpd      = 'Actualizado'
    AddonAt       = '{0} en {1}'
    S6            = '6. Configuración de Claude Desktop'
    S6Name        = '6. Config Claude'
    CfgSkipParam  = 'Omitido por parámetro -SkipClaudeConfig'
    CfgFile       = 'Fichero: {0}'
    CfgBadJson    = 'claude_desktop_config.json no es JSON válido. Corrígelo a mano: {0}'
    CfgOk         = 'La entrada "freecad" ya está configurada correctamente (modo: {0})'
    CfgOkS        = 'Ya presente ({0})'
    ModeText      = 'solo texto'
    ModeImage     = 'imágenes + texto'
    FbTitle       = 'Modo de respuesta de FreeCAD hacia Claude:'
    FbImage       = '- Imágenes + texto: cada operación devuelve además una captura del modelo. Claude ve el resultado, pero cada captura consume bastantes más tokens.'
    FbText        = '- Solo texto (--only-text-feedback): devuelve nombres, dimensiones y éxito/error. Consume muchos menos tokens; Claude puede seguir pidiendo una vista cuando la necesite (get_view).'
    FbAsk         = '¿Usar el modo solo texto para ahorrar tokens? (S/N)'
    FbCurrent     = 'Modo actual: {0}'
    FbKeep        = 'Enter = mantener {0}'
    FbParam       = 'Modo fijado por parámetro -Feedback: {0}'
    CfgNew        = 'No había configuración: se crea'
    CfgBackup     = 'Copia de seguridad: {0}'
    CfgUpdated    = 'Entrada "freecad" actualizada (modo: {0})'
    CfgAdded      = 'Entrada "freecad" añadida (modo: {0})'
    S7            = '7. Auto-inicio del servidor RPC'
    S7Name        = '7. Auto-inicio RPC'
    S8            = '8. Seguridad del servidor RPC'
    S8Name        = '8. Seguridad RPC'
    S9            = '9. FreeCAD y servidor RPC en ejecución'
    S9Name        = '9. Estado RPC'
    SetFile       = 'Ajustes del addon: {0}'
    SetMissing    = 'Aún no hay fichero de ajustes (valores por defecto: sin auto-inicio, solo 127.0.0.1)'
    SetBadJson    = 'El fichero de ajustes no es JSON válido; no se modifica: {0}'
    AutoOn        = 'El auto-inicio del servidor RPC ya está activado'
    AutoOnS       = 'Ya activado'
    AutoAsk       = '¿Quieres que el servidor MCP se auto-inicie siempre con FreeCAD? (S/N)'
    AutoEnabled   = 'Auto-inicio activado (se aplica la próxima vez que abras FreeCAD)'
    AutoEnabledS  = 'Activado'
    AutoDeclined  = 'Auto-inicio no activado: tendrás que pulsar Start RPC Server cada vez'
    AutoDeclinedS = 'Rechazado por el usuario'
    SecOk         = 'Lista de IPs permitidas: solo localhost ({0})'
    SecOkS        = 'Solo localhost'
    SecIps        = 'ATENCIÓN: la lista de IPs permitidas incluye direcciones que no son localhost: {0}'
    SecRemote     = 'ATENCIÓN: las conexiones remotas están ACTIVADAS (el servidor escucha en todas las interfaces)'
    SecNoToken    = 'ATENCIÓN: conexiones remotas sin token de autenticación: cualquiera desde esas IPs puede ejecutar código en FreeCAD'
    SecHint       = 'Si no lo has configurado tú a propósito, en FreeCAD: menú FreeCAD MCP -> Configure Allowed IPs / Toggle Remote Connections'
    SecWarnS      = '{0} advertencia(s)'
    FcRunning     = 'FreeCAD está en ejecución (PID {0})'
    FcNotRunning  = 'FreeCAD no está en ejecución'
    FcLaunchAsk   = '¿Quieres abrir FreeCAD ahora? (S/N)'
    FcLaunching   = 'Abriendo FreeCAD...'
    FcExeMissing  = 'No se encuentra FreeCAD.exe para abrirlo; ábrelo tú manualmente'
    RpcUp         = 'Servidor RPC escuchando en {0}:{1}'
    RpcUpExposed  = 'ATENCIÓN: el servidor RPC escucha en {0}:{1}, accesible desde la red'
    RpcDown       = 'El servidor RPC no está escuchando en el puerto {0}'
    RpcWait       = 'Esperando a que FreeCAD arranque el servidor RPC...'
    S10           = '10. Claude Desktop'
    S10Name       = '10. Claude Desktop'
    ClRunning     = 'Claude Desktop está en ejecución'
    ClRunningS    = 'En ejecución'
    ClNotRunning  = 'Claude Desktop no está en ejecución'
    ClNotRunningS = 'No iniciado'
    NextTitle     = 'Siguientes pasos:'
    AllReady      = 'Todo listo: pide a Claude una pieza sencilla en FreeCAD para probar.'
    NsRestartFcAddon = 'Reinicia FreeCAD para que cargue el addon instalado o actualizado'
    NsOpenFcAuto  = 'Abre FreeCAD: el servidor RPC arrancará solo'
    NsOpenFcManual = 'Abre FreeCAD -> workbench MCP Addon -> Start RPC Server'
    NsRestartFcAuto = 'Reinicia FreeCAD para que se aplique el auto-inicio (o pulsa ya Start RPC Server en el workbench MCP Addon)'
    NsStartRpc    = 'En FreeCAD: workbench MCP Addon -> Start RPC Server'
    NsCheckFc     = 'FreeCAD se abrió pero el RPC no arrancó en 60 s: revisa la Vista de informe de FreeCAD (mensajes [MCP])'
    NsRestartClaude = 'Cierra Claude Desktop del todo (también desde la bandeja del sistema) y vuelve a abrirlo para cargar la nueva configuración'
    NsOpenClaude  = 'Abre Claude Desktop'
    SecNote       = 'Recuerda: NO actives las conexiones remotas del addon sin revisar antes la seguridad y el acceso de red.'
    NsTry         = 'Después, pide a Claude una pieza sencilla en FreeCAD para probar'
    Summary       = 'Resumen'
    NothingDone   = 'Todo estaba ya instalado y configurado. No se ha cambiado nada.'
    Completed     = 'Instalación completada ({0} paso(s) aplicados).'
  }
  en = @{
    Subtitle      = 'Claude Desktop <-> FreeCAD MCP bridge installer'
    ForceMode     = '-Force mode: every step will be redone'
    Done          = 'Done'
    Skipped       = 'Skipped'
    S1            = '1. Working directory: {0}'
    S1Name        = '1. Working directory'
    Exists        = 'Already exists'
    Existed       = 'Already existed'
    Created       = 'Created'
    S2            = '2. Repository neka-nat/freecad-mcp'
    S2Name        = '2. Repository'
    GitPullFail   = 'git pull failed in {0}'
    UpToDate      = 'Already up to date ({0})'
    UpToDateShort = 'Up to date ({0})'
    Updated       = 'Updated {0} -> {1}'
    UpdatedTo     = 'Updated to {0}'
    ZipPresent    = 'Already downloaded (without git changes cannot be checked; use -Force to redo)'
    ZipPresentS   = 'Already downloaded (ZIP)'
    Cloned        = 'Cloned'
    CloneFail     = 'git clone failed'
    NoGit         = 'git not found: downloading as ZIP'
    ZipDone       = 'ZIP downloaded and extracted'
    ZipDoneS      = 'Downloaded (ZIP)'
    NoInitGui     = '{0}\InitGui.py not found. Has the repository layout changed?'
    S3            = '3. uv'
    UvPresent     = 'Already installed: {0}'
    UvInstalling  = 'Installing uv into {0}'
    UvFail        = 'uv installation did not leave uvx.exe in {0}'
    UvDone        = 'Installed: {0}'
    S4            = '4. FreeCAD user folder'
    S4Name        = '4. Mod folder'
    ParamPath     = 'Path given by parameter: {0}'
    FcNotFound    = 'FreeCAD user folder not found in {0}\FreeCAD\vX-Y'
    FcHint1       = 'FreeCAD creates it the first time it is opened after installation.'
    FcHint2       = 'Open FreeCAD, wait until it has fully loaded, then close it.'
    FcAsk         = 'Have you opened and closed it at least once? (Y/N)'
    Yes           = 'Y'
    No            = 'N'
    FcStopped     = 'Installation stopped. Open FreeCAD once and run the script again.'
    FcMissing     = 'FreeCAD user folder does not exist: {0}'
    FcUserDir     = 'User folder: {0}'
    ModExists     = 'Mod folder already exists: {0}'
    ModCreating   = 'Mod folder does not exist: creating {0}'
    ModCreated    = 'Mod folder created'
    CreatedF      = 'Created'
    ModFail       = 'Could not create {0} : {1}'
    S5            = '5. {0} addon'
    S5Name        = '5. Addon'
    AddonSame     = 'Already installed and identical to the repository: {0}'
    AddonSameS    = 'Already installed, unchanged'
    AddonInst     = 'Installed'
    AddonUpd      = 'Updated'
    AddonAt       = '{0} in {1}'
    S6            = '6. Claude Desktop configuration'
    S6Name        = '6. Claude config'
    CfgSkipParam  = 'Skipped by -SkipClaudeConfig'
    CfgFile       = 'File: {0}'
    CfgBadJson    = 'claude_desktop_config.json is not valid JSON. Fix it manually: {0}'
    CfgOk         = 'The "freecad" entry is already configured correctly (mode: {0})'
    CfgOkS        = 'Already present ({0})'
    ModeText      = 'text only'
    ModeImage     = 'images + text'
    FbTitle       = 'FreeCAD feedback mode towards Claude:'
    FbImage       = '- Images + text: every operation also returns a screenshot of the model. Claude sees the result, but each screenshot costs considerably more tokens.'
    FbText        = '- Text only (--only-text-feedback): returns object names, dimensions and success/error. Uses far fewer tokens; Claude can still ask for a view when needed (get_view).'
    FbAsk         = 'Use text-only mode to save tokens? (Y/N)'
    FbCurrent     = 'Current mode: {0}'
    FbKeep        = 'Enter = keep {0}'
    FbParam       = 'Mode set by -Feedback parameter: {0}'
    CfgNew        = 'No configuration found: creating it'
    CfgBackup     = 'Backup: {0}'
    CfgUpdated    = '"freecad" entry updated (mode: {0})'
    CfgAdded      = '"freecad" entry added (mode: {0})'
    S7            = '7. RPC server auto-start'
    S7Name        = '7. RPC auto-start'
    S8            = '8. RPC server security'
    S8Name        = '8. RPC security'
    S9            = '9. FreeCAD and RPC server running'
    S9Name        = '9. RPC status'
    SetFile       = 'Addon settings: {0}'
    SetMissing    = 'No settings file yet (defaults: no auto-start, 127.0.0.1 only)'
    SetBadJson    = 'The settings file is not valid JSON; leaving it untouched: {0}'
    AutoOn        = 'RPC server auto-start is already enabled'
    AutoOnS       = 'Already enabled'
    AutoAsk       = 'Do you want the MCP server to always auto-start with FreeCAD? (Y/N)'
    AutoEnabled   = 'Auto-start enabled (applies the next time you open FreeCAD)'
    AutoEnabledS  = 'Enabled'
    AutoDeclined  = 'Auto-start not enabled: you will have to click Start RPC Server every time'
    AutoDeclinedS = 'Declined by user'
    SecOk         = 'Allowed IP list: localhost only ({0})'
    SecOkS        = 'Localhost only'
    SecIps        = 'WARNING: the allowed IP list includes non-localhost addresses: {0}'
    SecRemote     = 'WARNING: remote connections are ENABLED (the server listens on all interfaces)'
    SecNoToken    = 'WARNING: remote connections without an auth token: anyone on those IPs can run code in FreeCAD'
    SecHint       = 'If you did not set this on purpose, in FreeCAD: FreeCAD MCP menu -> Configure Allowed IPs / Toggle Remote Connections'
    SecWarnS      = '{0} warning(s)'
    FcRunning     = 'FreeCAD is running (PID {0})'
    FcNotRunning  = 'FreeCAD is not running'
    FcLaunchAsk   = 'Do you want to open FreeCAD now? (Y/N)'
    FcLaunching   = 'Opening FreeCAD...'
    FcExeMissing  = 'FreeCAD.exe not found; please open it manually'
    RpcUp         = 'RPC server listening on {0}:{1}'
    RpcUpExposed  = 'WARNING: the RPC server listens on {0}:{1}, reachable from the network'
    RpcDown       = 'The RPC server is not listening on port {0}'
    RpcWait       = 'Waiting for FreeCAD to start the RPC server...'
    S10           = '10. Claude Desktop'
    S10Name       = '10. Claude Desktop'
    ClRunning     = 'Claude Desktop is running'
    ClRunningS    = 'Running'
    ClNotRunning  = 'Claude Desktop is not running'
    ClNotRunningS = 'Not running'
    NextTitle     = 'Next steps:'
    AllReady      = 'All set: ask Claude for a simple part in FreeCAD to try it out.'
    NsRestartFcAddon = 'Restart FreeCAD so it loads the installed or updated addon'
    NsOpenFcAuto  = 'Open FreeCAD: the RPC server will start on its own'
    NsOpenFcManual = 'Open FreeCAD -> MCP Addon workbench -> Start RPC Server'
    NsRestartFcAuto = 'Restart FreeCAD so auto-start takes effect (or click Start RPC Server in the MCP Addon workbench now)'
    NsStartRpc    = 'In FreeCAD: MCP Addon workbench -> Start RPC Server'
    NsCheckFc     = 'FreeCAD opened but the RPC server did not start within 60 s: check FreeCAD''s Report view ([MCP] messages)'
    NsRestartClaude = 'Fully quit Claude Desktop (including from the system tray) and reopen it to load the new configuration'
    NsOpenClaude  = 'Open Claude Desktop'
    SecNote       = 'Remember: do NOT enable the addon''s remote connections without first reviewing security and network access.'
    NsTry         = 'Then ask Claude for a simple part in FreeCAD to try it out'
    Summary       = 'Summary'
    NothingDone   = 'Everything was already installed and configured. Nothing was changed.'
    Completed     = 'Installation completed ({0} step(s) applied).'
  }
}

# ---------------------------------------------------------------------------
# Idioma / Language
# ---------------------------------------------------------------------------
if (-not $Lang) {
    $detected = if ((Get-UICulture).TwoLetterISOLanguageName -eq 'es') { 'es' } else { 'en' }
    do {
        $answer = (Read-Host "Idioma / Language [es/en] (Enter = $detected)").Trim().ToLower()
        if (-not $answer) { $answer = $detected }
    } until ($answer -in 'es', 'en')
    $Lang = $answer
}
$L = $Strings[$Lang]
function T([string]$Key) { $L[$Key] -f $args }

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
$banner = @'
  ____ _                 _                 ____    _    ____
 / ___| | __ _ _   _  __| | ___     _     / ___|  / \  |  _ \
| |   | |/ _` | | | |/ _` |/ _ \  _| |_  | |     / _ \ | | | |
| |___| | (_| | |_| | (_| |  __/ |_   _| | |___ / ___ \| |_| |
 \____|_|\__,_|\__,_|\__,_|\___|   |_|    \____/_/   \_\____/
'@
Write-Host ''
Write-Host $banner -ForegroundColor DarkYellow
Write-Host ('{0,62}' -f "by mainmind.com  ·  v$ScriptVersion") -ForegroundColor Gray
Write-Host ('  ' + ('-' * 60)) -ForegroundColor DarkGray
Write-Host "  $(T Subtitle)" -ForegroundColor Gray
if ($Force) { Write-Host "  $(T ForceMode)" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# Utilidades / Helpers
# ---------------------------------------------------------------------------
$Summary = [System.Collections.Generic.List[object]]::new()
function Add-Result([string]$Step, [bool]$IsDone, [string]$Detail) {
    $Summary.Add([pscustomobject]@{ Step = $Step; IsDone = $IsDone; Detail = $Detail })
}
function Write-Step($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "    [OK]   $msg" -ForegroundColor Green }
function Write-Skip($msg)  { Write-Host "    [SKIP] $msg" -ForegroundColor DarkGray }
function Write-Warn2($msg) { Write-Host "    [!]    $msg" -ForegroundColor Yellow }

# Pregunta S/N (o Y/N) / Yes-No prompt
function Ask-YesNo([string]$Question) {
    $yes = T Yes; $no = T No
    do { $r = (Read-Host "           $Question").Trim().ToUpper() } until ($r -in $yes, $no)
    return ($r -eq $yes)
}

# UTF-8 sin BOM / without BOM (PS 5.1 -Encoding UTF8 adds a BOM)
function Write-Utf8NoBom([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

# Huella de carpeta / Folder fingerprint: relative path + SHA256 (ignores __pycache__)
function Get-DirFingerprint([string]$Path) {
    if (-not (Test-Path $Path)) { return $null }
    $root = (Resolve-Path $Path).Path.TrimEnd('\')
    $lines = Get-ChildItem $root -Recurse -File |
             Where-Object { $_.FullName -notmatch '\\__pycache__\\' -and $_.Extension -ne '.pyc' } |
             Sort-Object FullName |
             ForEach-Object { $_.FullName.Substring($root.Length) + '|' + (Get-FileHash $_.FullName -Algorithm SHA256).Hash }
    return ($lines -join "`n")
}

# Estado inicial de FreeCAD (para saber si cargó el addon antiguo) / Initial FreeCAD state
$fcRunningAtStart = [bool](Get-Process -Name 'FreeCAD' -ErrorAction SilentlyContinue)

# ---------------------------------------------------------------------------
# 1. Directorio de trabajo / Working directory
# ---------------------------------------------------------------------------
Write-Step (T S1 $WorkDir)
if (Test-Path $WorkDir) {
    Write-Skip (T Exists)
    Add-Result (T S1Name) $false (T Existed)
} else {
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    Write-Ok (T Created)
    Add-Result (T S1Name) $true (T Created)
}

# ---------------------------------------------------------------------------
# 2. Repositorio / Repository
# ---------------------------------------------------------------------------
Write-Step (T S2)
$git = Get-Command git -ErrorAction SilentlyContinue

if ($git -and (Test-Path (Join-Path $RepoDir '.git')) -and -not $Force) {
    $before = (git -C $RepoDir rev-parse HEAD).Trim()
    git -C $RepoDir pull --ff-only --quiet
    if ($LASTEXITCODE -ne 0) { throw (T GitPullFail $RepoDir) }
    $after = (git -C $RepoDir rev-parse HEAD).Trim()
    if ($before -eq $after) {
        Write-Skip (T UpToDate $after.Substring(0,7))
        Add-Result (T S2Name) $false (T UpToDateShort $after.Substring(0,7))
    } else {
        Write-Ok (T Updated $before.Substring(0,7) $after.Substring(0,7))
        Add-Result (T S2Name) $true (T UpdatedTo $after.Substring(0,7))
    }
} elseif (-not $git -and (Test-Path (Join-Path $RepoDir "addon\$AddonName\InitGui.py")) -and -not $Force) {
    Write-Skip (T ZipPresent)
    Add-Result (T S2Name) $false (T ZipPresentS)
} else {
    if (Test-Path $RepoDir) { Remove-Item $RepoDir -Recurse -Force }
    if ($git) {
        git clone --depth 1 --quiet $RepoUrl $RepoDir
        if ($LASTEXITCODE -ne 0) { throw (T CloneFail) }
        Write-Ok (T Cloned)
        Add-Result (T S2Name) $true (T Cloned)
    } else {
        Write-Warn2 (T NoGit)
        $zip = Join-Path $WorkDir 'freecad-mcp.zip'
        $tmp = Join-Path $WorkDir '_extract'
        Invoke-WebRequest -Uri $ZipUrl -OutFile $zip -UseBasicParsing
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        Move-Item (Get-ChildItem $tmp -Directory | Select-Object -First 1).FullName $RepoDir
        Remove-Item $tmp -Recurse -Force
        Remove-Item $zip -Force
        Write-Ok (T ZipDone)
        Add-Result (T S2Name) $true (T ZipDoneS)
    }
}

$AddonSrc = Join-Path $RepoDir "addon\$AddonName"
if (-not (Test-Path (Join-Path $AddonSrc 'InitGui.py'))) { throw (T NoInitGui $AddonSrc) }

# ---------------------------------------------------------------------------
# 3. uv (WorkDir\bin, sin tocar perfil ni PATH / no profile or PATH changes)
# ---------------------------------------------------------------------------
Write-Step (T S3)
$uvBin   = Join-Path $WorkDir 'bin'
$UvxPath = Join-Path $uvBin 'uvx.exe'

if ((Test-Path $UvxPath) -and -not $Force) {
    $ver = (& $UvxPath --version) -join ' '
    Write-Skip (T UvPresent $ver)
    Add-Result (T S3) $false $ver
} else {
    Write-Warn2 (T UvInstalling $uvBin)
    $env:UV_INSTALL_DIR    = $uvBin
    $env:UV_NO_MODIFY_PATH = '1'
    powershell -NoProfile -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
    if (-not (Test-Path $UvxPath)) { throw (T UvFail $uvBin) }
    $ver = (& $UvxPath --version) -join ' '
    Write-Ok (T UvDone $ver)
    Add-Result (T S3) $true $ver
}

# ---------------------------------------------------------------------------
# 4. Carpeta de usuario de FreeCAD y Mod / FreeCAD user folder and Mod
# ---------------------------------------------------------------------------
Write-Step (T S4)

# %APPDATA%\FreeCAD\vX-Y (FreeCAD >= 1.1: one folder per version)
function Find-FreeCADUserDir {
    $base = Join-Path $env:APPDATA 'FreeCAD'
    if (-not (Test-Path $base)) { return $null }
    $versioned = Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match '^v\d+-\d+$' } |
                 Sort-Object { [version]($_.Name.Substring(1) -replace '-', '.') } -Descending |
                 Select-Object -First 1
    if ($versioned) { return $versioned.FullName }
    return $null
}

if ($FreeCADUserDir) {
    Write-Ok (T ParamPath $FreeCADUserDir)
} else {
    $FreeCADUserDir = Find-FreeCADUserDir
    while (-not $FreeCADUserDir) {
        Write-Warn2 (T FcNotFound $env:APPDATA)
        Write-Host  "           $(T FcHint1)" -ForegroundColor Yellow
        Write-Host  "           $(T FcHint2)" -ForegroundColor Yellow
        $yes = T Yes; $no = T No
        do {
            $resp = (Read-Host "           $(T FcAsk)").Trim().ToUpper()
        } until ($resp -in $yes, $no)
        if ($resp -eq $no) {
            Write-Host "`n$(T FcStopped)" -ForegroundColor Yellow
            exit 1
        }
        $FreeCADUserDir = Find-FreeCADUserDir
    }
}

if (-not (Test-Path $FreeCADUserDir)) { throw (T FcMissing $FreeCADUserDir) }
Write-Ok (T FcUserDir $FreeCADUserDir)

$ModDir   = Join-Path $FreeCADUserDir 'Mod'
$AddonDst = Join-Path $ModDir $AddonName

if (Test-Path $ModDir) {
    Write-Skip (T ModExists $ModDir)
    Add-Result (T S4Name) $false (T Existed)
} else {
    Write-Warn2 (T ModCreating $ModDir)
    try {
        New-Item -ItemType Directory -Path $ModDir -Force -ErrorAction Stop | Out-Null
        Write-Ok (T ModCreated)
        Add-Result (T S4Name) $true (T CreatedF)
    } catch {
        throw (T ModFail $ModDir $_.Exception.Message)
    }
}

# ---------------------------------------------------------------------------
# 5. Addon FreeCADMCP
# ---------------------------------------------------------------------------
Write-Step (T S5 $AddonName)

$srcPrint = Get-DirFingerprint $AddonSrc
$dstPrint = Get-DirFingerprint $AddonDst

if (($srcPrint -eq $dstPrint) -and -not $Force) {
    Write-Skip (T AddonSame $AddonDst)
    Add-Result (T S5Name) $false (T AddonSameS)
} else {
    $action = if ($dstPrint) { T AddonUpd } else { T AddonInst }
    if (Test-Path $AddonDst) { Remove-Item $AddonDst -Recurse -Force }
    Copy-Item $AddonSrc $AddonDst -Recurse -Force
    Write-Ok (T AddonAt $action $AddonDst)
    Add-Result (T S5Name) $true $action
}

# ---------------------------------------------------------------------------
# 6. Configuración de Claude Desktop / Claude Desktop configuration
# ---------------------------------------------------------------------------
Write-Step (T S6)

if ($SkipClaudeConfig) {
    Write-Skip (T CfgSkipParam)
    Add-Result (T S6Name) $false '-SkipClaudeConfig'
} else {
    # Instalación clásica vs. MSIX (Microsoft Store) / Classic vs. MSIX install
    $candidates = @(Join-Path $env:APPDATA 'Claude\claude_desktop_config.json')
    $candidates += Get-ChildItem "$env:LOCALAPPDATA\Packages\Claude_*\LocalCache\Roaming\Claude" -Directory -ErrorAction SilentlyContinue |
                   ForEach-Object { Join-Path $_.FullName 'claude_desktop_config.json' }

    $cfgPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    $isNew = -not $cfgPath
    if ($isNew) { $cfgPath = $candidates[0] }
    Write-Ok (T CfgFile $cfgPath)

    $cfg = [pscustomobject]@{}
    if (-not $isNew) {
        $raw = Get-Content $cfgPath -Raw -Encoding UTF8
        if ($raw -and $raw.Trim()) {
            try { $cfg = $raw | ConvertFrom-Json }
            catch { throw (T CfgBadJson $cfgPath) }
        }
    }

    $current = $null
    if (($cfg.PSObject.Properties.Name -contains 'mcpServers') -and
        ($cfg.mcpServers.PSObject.Properties.Name -contains 'freecad')) {
        $current = $cfg.mcpServers.freecad
    }
    # Modo de respuesta / Feedback mode
    $TextFlag  = '--only-text-feedback'
    $curArgs   = if ($current) { @($current.args) } else { @() }
    $curText   = $curArgs -contains $TextFlag
    # Conservar otros argumentos que haya puesto el usuario (p. ej. --host) / keep user's extra args
    $extraArgs = @($curArgs | Where-Object { $_ -ne 'freecad-mcp' -and $_ -ne $TextFlag })
    $baseOk    = $current -and ($current.command -eq $UvxPath) -and ($curArgs.Count -gt 0) -and ($curArgs[0] -eq 'freecad-mcp')

    if ($Feedback) {
        $wantText = ($Feedback -eq 'text')
        Write-Ok (T FbParam $(if ($wantText) { T ModeText } else { T ModeImage }))
    } else {
        # Se explica y pregunta siempre; si la respuesta coincide con el modo actual, no se toca el fichero
        Write-Host "           $(T FbTitle)" -ForegroundColor Gray
        Write-Host "             $(T FbImage)" -ForegroundColor Gray
        Write-Host "             $(T FbText)"  -ForegroundColor Gray
        $question = T FbAsk
        if ($current) {
            $curName = if ($curText) { T ModeText } else { T ModeImage }
            Write-Host "           $(T FbCurrent $curName)" -ForegroundColor Cyan
            $question = $question.TrimEnd(')') + ', ' + (T FbKeep $curName) + ')'
        }
        $yes = T Yes; $no = T No
        do {
            $r = (Read-Host "           $question").Trim().ToUpper()
            if (-not $r -and $current) { $r = if ($curText) { $yes } else { $no } }
        } until ($r -in $yes, $no)
        $wantText = ($r -eq $yes)
    }
    $modeName = if ($wantText) { T ModeText } else { T ModeImage }
    $upToDate = $baseOk -and ($curText -eq $wantText)

    if ($upToDate -and -not $Force) {
        Write-Skip (T CfgOk $modeName)
        Add-Result (T S6Name) $false (T CfgOkS $modeName)
    } else {
        if ($isNew) {
            New-Item -ItemType Directory -Path (Split-Path $cfgPath) -Force | Out-Null
            Write-Warn2 (T CfgNew)
        } else {
            $backup = "$cfgPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item $cfgPath $backup
            Write-Ok (T CfgBackup $backup)
        }

        if (-not ($cfg.PSObject.Properties.Name -contains 'mcpServers')) {
            $cfg | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{})
        }
        $newArgs = @('freecad-mcp')
        if ($wantText) { $newArgs += $TextFlag }
        $newArgs += $extraArgs
        # Ruta absoluta a uvx / Absolute uvx path: Claude Desktop may not inherit PATH
        $server = [ordered]@{ command = $UvxPath; args = $newArgs }
        if ($current -and ($current.PSObject.Properties.Name -contains 'env')) { $server.env = $current.env }
        $server = [pscustomobject]$server
        if ($current) {
            $cfg.mcpServers.freecad = $server
            $action = T CfgUpdated $modeName
        } else {
            $cfg.mcpServers | Add-Member -NotePropertyName freecad -NotePropertyValue $server
            $action = T CfgAdded $modeName
        }
        Write-Utf8NoBom $cfgPath ($cfg | ConvertTo-Json -Depth 20)
        Write-Ok $action
        Add-Result (T S6Name) $true $action
    }
}

# ---------------------------------------------------------------------------
# 7. Auto-inicio del servidor RPC / RPC server auto-start
# ---------------------------------------------------------------------------
Write-Step (T S7)

# 7a. Ajustes del addon / Addon settings  (<FreeCADUserDir>\freecad_mcp_settings.json)
$SettingsPath = Join-Path $FreeCADUserDir 'freecad_mcp_settings.json'
$defaults = [ordered]@{ remote_enabled = $false; allowed_ips = '127.0.0.1'; auto_start_rpc = $false; auth_token = '' }
$settings = [pscustomobject]$defaults
$settingsValid = $true
if (Test-Path $SettingsPath) {
    Write-Ok (T SetFile $SettingsPath)
    try {
        $settings = Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($k in $defaults.Keys) {
            if (-not ($settings.PSObject.Properties.Name -contains $k)) {
                $settings | Add-Member -NotePropertyName $k -NotePropertyValue $defaults[$k]
            }
        }
    } catch {
        $settingsValid = $false
        Write-Warn2 (T SetBadJson $SettingsPath)
    }
} else {
    Write-Skip (T SetMissing)
}

# 7b. Auto-inicio / Auto-start
if (-not $settingsValid) {
    Add-Result (T S7Name) $false (T SetBadJson '')
} elseif ($settings.auto_start_rpc -eq $true) {
    Write-Skip (T AutoOn)
    Add-Result (T S7Name) $false (T AutoOnS)
} elseif (Ask-YesNo (T AutoAsk)) {
    $settings.auto_start_rpc = $true
    # Sin BOM: el addon abre el fichero con json.load y la codificación por defecto de Windows
    Write-Utf8NoBom $SettingsPath ($settings | ConvertTo-Json -Depth 5)
    Write-Ok (T AutoEnabled)
    Add-Result (T S7Name) $true (T AutoEnabledS)
} else {
    Write-Warn2 (T AutoDeclined)
    Add-Result (T S7Name) $false (T AutoDeclinedS)
}

# ---------------------------------------------------------------------------
# 8. Seguridad: IPs permitidas, remoto, token / Security: allowed IPs, remote, token
# ---------------------------------------------------------------------------
Write-Step (T S8)
function Test-IsLoopback([string]$Entry) {
    $e = $Entry.Trim()
    if ($e -eq 'localhost') { return $true }
    $ipPart = ($e -split '/')[0]
    $ip = $null
    if (-not [System.Net.IPAddress]::TryParse($ipPart, [ref]$ip)) { return $false }
    return [System.Net.IPAddress]::IsLoopback($ip)
}
$warnings = 0
if ($settingsValid) {
    $ipList  = @("$($settings.allowed_ips)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $foreign = @($ipList | Where-Object { -not (Test-IsLoopback $_) })
    if ($foreign.Count -gt 0) { Write-Warn2 (T SecIps ($foreign -join ', ')); $warnings++ }
    if ($settings.remote_enabled -eq $true) {
        Write-Warn2 (T SecRemote); $warnings++
        if (-not "$($settings.auth_token)") { Write-Warn2 (T SecNoToken); $warnings++ }
    }
    if ($warnings -eq 0) {
        Write-Ok (T SecOk ($ipList -join ', '))
        Add-Result (T S8Name) $false (T SecOkS)
    } else {
        Write-Host "           $(T SecHint)" -ForegroundColor Yellow
        Add-Result (T S8Name) $false (T SecWarnS $warnings)
    }
}

# ---------------------------------------------------------------------------
# 9. FreeCAD y servidor RPC en ejecución / FreeCAD and RPC server running
# ---------------------------------------------------------------------------
Write-Step (T S9)

# 9a. ¿FreeCAD en ejecución? / Is FreeCAD running?
function Get-FreeCADProcess { Get-Process -Name 'FreeCAD' -ErrorAction SilentlyContinue | Select-Object -First 1 }
$launched = $false
$fcProc = Get-FreeCADProcess
if ($fcProc) {
    Write-Ok (T FcRunning $fcProc.Id)
} else {
    Write-Warn2 (T FcNotRunning)
    if (Ask-YesNo (T FcLaunchAsk)) {
        $fcExe = Get-ChildItem -Path "$env:ProgramFiles\FreeCAD*\bin\FreeCAD.exe",
                                     "$env:LOCALAPPDATA\Programs\FreeCAD*\bin\FreeCAD.exe" `
                               -ErrorAction SilentlyContinue |
                 Sort-Object FullName -Descending | Select-Object -First 1
        if ($fcExe) {
            Write-Ok (T FcLaunching)
            Start-Process $fcExe.FullName
            $launched = $true
            # Si el auto-inicio está activo, esperar hasta 60 s a que abra el puerto
            if ($settings.auto_start_rpc -eq $true) {
                Write-Host "           $(T RpcWait)" -ForegroundColor DarkGray
                for ($i = 0; $i -lt 30; $i++) {
                    Start-Sleep -Seconds 2
                    if (Get-NetTCPConnection -LocalPort $RpcPort -State Listen -ErrorAction SilentlyContinue) { break }
                }
            } else {
                Start-Sleep -Seconds 5
            }
            $fcProc = Get-FreeCADProcess
        } else {
            Write-Warn2 (T FcExeMissing)
        }
    }
}

# 9b. ¿Servidor RPC escuchando? / Is the RPC server listening?
$rpcDetail = T FcNotRunning
$rpcListening = $false
if ($fcProc) {
    $listen = @(Get-NetTCPConnection -LocalPort $RpcPort -State Listen -ErrorAction SilentlyContinue)
    if ($listen.Count -gt 0) {
        $rpcListening = $true
        $addrs = @()
        foreach ($c in $listen) {
            $addrs += "$($c.LocalAddress):$RpcPort"
            if ((Test-IsLoopback $c.LocalAddress)) {
                Write-Ok (T RpcUp $c.LocalAddress $RpcPort)
            } else {
                Write-Warn2 (T RpcUpExposed $c.LocalAddress $RpcPort)
            }
        }
        $rpcDetail = 'RPC ' + ($addrs -join ', ')
    } else {
        Write-Warn2 (T RpcDown $RpcPort)
        $rpcDetail = T RpcDown $RpcPort
    }
}
Add-Result (T S9Name) $launched $rpcDetail

# ---------------------------------------------------------------------------
# 10. Claude Desktop
# ---------------------------------------------------------------------------
Write-Step (T S10)
# claude.exe también puede ser Claude Code (CLI): se filtra por ruta de instalación de la app
$clProc = Get-Process -Name 'claude' -ErrorAction SilentlyContinue |
          Where-Object {
              ($_.Path -and $_.Path -match 'AnthropicClaude|\\WindowsApps\\Claude_|\\Programs\\Claude\\') -or
              (-not $_.Path -and $_.MainWindowHandle -ne 0)
          } | Select-Object -First 1
if ($clProc) {
    Write-Ok (T ClRunning)
    Add-Result (T S10Name) $false (T ClRunningS)
} else {
    Write-Skip (T ClNotRunning)
    Add-Result (T S10Name) $false (T ClNotRunningS)
}

# ---------------------------------------------------------------------------
# Resumen / Summary
# ---------------------------------------------------------------------------
Write-Host "`n  $(T Summary)" -ForegroundColor Cyan
Write-Host ('  ' + ('-' * 60)) -ForegroundColor DarkGray
foreach ($r in $Summary) {
    $status = if ($r.IsDone) { T Done } else { T Skipped }
    $color  = if ($r.IsDone) { 'Green' } else { 'DarkGray' }
    Write-Host ('  {0,-26} {1,-8} {2}' -f $r.Step, $status, $r.Detail) -ForegroundColor $color
}

$changed = @($Summary | Where-Object IsDone).Count
if ($changed -eq 0) {
    Write-Host "`n  $(T NothingDone)" -ForegroundColor Green
} else {
    Write-Host "`n  $(T Completed $changed)" -ForegroundColor Green
}

# Siguientes pasos según el estado real / Next steps based on actual state
function Test-StepDone([string]$NameKey) {
    [bool]($Summary | Where-Object { $_.Step -eq (T $NameKey) -and $_.IsDone })
}
$addonChanged = Test-StepDone 'S5Name'
$cfgChanged   = Test-StepDone 'S6Name'
$autoChanged  = Test-StepDone 'S7Name'
$autoOn       = $settingsValid -and ($settings.auto_start_rpc -eq $true)

$next = @()
if ($fcProc) {
    if ($addonChanged -and $fcRunningAtStart) {
        $next += T NsRestartFcAddon            # FreeCAD tenía cargado el addon antiguo (o ninguno)
    } elseif (-not $rpcListening) {
        if ($launched -and $autoOn)               { $next += T NsCheckFc }
        elseif ($autoChanged -and -not $launched) { $next += T NsRestartFcAuto }
        else                                      { $next += T NsStartRpc }
    }
} else {
    $next += if ($autoOn) { T NsOpenFcAuto } else { T NsOpenFcManual }
}

if ($cfgChanged) {
    $next += if ($clProc) { T NsRestartClaude } else { T NsOpenClaude }
} elseif (-not $clProc) {
    $next += T NsOpenClaude
}

if ($next.Count -eq 0) {
    Write-Host "`n  $(T AllReady)" -ForegroundColor Green
} else {
    Write-Host "`n  $(T NextTitle)" -ForegroundColor Cyan
    for ($i = 0; $i -lt $next.Count; $i++) { Write-Host ("    {0}. {1}" -f ($i + 1), $next[$i]) }
    Write-Host ("    {0}. {1}" -f ($next.Count + 1), (T NsTry))
}
Write-Host "`n  $(T SecNote)" -ForegroundColor Yellow
Write-Host ''
