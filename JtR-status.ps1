<#
Este script está disponible bajo la licencia MIT.
Copyright (c) 2025 Kaizen Development Solutions.

Se permite el uso, copia, modificación y distribución del software
siempre que se mantenga este aviso de copyright y la referencia a la
licencia MIT. El software se proporciona "tal cual", sin garantías de
ningún tipo. Para más detalles consulte el archivo LICENSE del
repositorio.

.SYNOPSIS
Muestra el estado de sesiones activas de John the Ripper en Windows,
permitiendo refresco automático y autodetección del ejecutable john.exe.

.DESCRIPTION
Este script lista las sesiones .rec en el directorio del usuario,
permite seleccionar una, detecta automáticamente si John está ejecutando
esa sesión y muestra el progreso con formato compacto y marca temporal.

.EXAMPLE
.\jtr-status.ps1

Muestra la lista de sesiones y realiza una consulta del estado.

.EXAMPLE
.\jtr-status.ps1 -RefreshSeconds 30

Refresca continuamente el estado de la sesión seleccionada cada
30 segundos hasta que deje de estar activa.
#>

param(
    # Ruta al ejecutable john.exe (se intentará autodetectar si no existe)
    [string]$JohnExe = "C:\DATOS\JtR\run\john.exe",

    # Intervalo de refresco en segundos.
    # 0 o negativo -> solo consulta una vez y termina.
    [int]$RefreshSeconds = 60
)

$sessionDir = Join-Path $env:USERPROFILE ".john\sessions"

# --- Autodetección de john.exe ---
if (-not (Test-Path $JohnExe)) {
    $candidates = @()

    # Carpetas base donde buscar
    $roots = @()
    if ($PSScriptRoot) { $roots += $PSScriptRoot }
    $roots += (Get-Location).Path

    foreach ($root in $roots) {
        $candidates += (Join-Path $root "john.exe")
        $candidates += (Join-Path $root "run\john.exe")
        $candidates += (Join-Path $root "JtR\john.exe")
        $candidates += (Join-Path $root "JtR\run\john.exe")
    }

    $found = $null
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            $found = $c
            break
        }
    }

    if ($found) {
        Write-Host ("john.exe no encontrado en la ruta configurada. Usando autodetectado: {0}" -f $found) -ForegroundColor Yellow
        $JohnExe = $found
    }
    else {
        Write-Host "ERROR: No se encontró john.exe. Revisa la variable `\$JohnExe` en el script o coloca john.exe en una de estas rutas:" -ForegroundColor Red
        Write-Host "  - (carpeta del script)\john.exe"
        Write-Host "  - (carpeta del script)\run\john.exe"
        Write-Host "  - (carpeta actual)\john.exe"
        Write-Host "  - (carpeta actual)\run\john.exe"
        Write-Host "  - (carpeta actual)\JtR\john.exe"
        Write-Host "  - (carpeta actual)\JtR\run\john.exe"
        exit 1
    }
}

if (-not (Test-Path $sessionDir)) {
    Write-Host "ERROR: No existe la carpeta de sesiones: $sessionDir" -ForegroundColor Red
    exit 1
}

# Obtener las sesiones .rec ordenadas por última modificación (más reciente primero)
$sessions = Get-ChildItem -Path $sessionDir -Filter "*.rec" |
            Sort-Object LastWriteTime -Descending

if ($sessions.Count -eq 0) {
    Write-Host "No se encontraron sesiones (.rec) en $sessionDir" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host ("Sesiones encontradas en {0}:" -f $sessionDir)
Write-Host ""

# La más reciente es la preseleccionada
$defaultIndex = 1

# Mostrar lista numerada
for ($i = 0; $i -lt $sessions.Count; $i++) {
    $idx  = $i + 1
    $name = [System.IO.Path]::GetFileNameWithoutExtension($sessions[$i].Name)
    $time = $sessions[$i].LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")

    if ($idx -eq $defaultIndex) {
        Write-Host ("[{0}] {1}  (última actividad: {2})  <-- RECIENTE" -f $idx, $name, $time) -ForegroundColor Cyan
    }
    else {
        Write-Host ("[{0}] {1}  (última actividad: {2})" -f $idx, $name, $time)
    }
}

# Preguntar selección
$selection = Read-Host ("Selecciona sesión (1-{0}) [ENTER = {1}]" -f $sessions.Count, $defaultIndex)

if ([string]::IsNullOrWhiteSpace($selection)) {
    $selection = $defaultIndex
}

if (-not ($selection -as [int]) -or $selection -lt 1 -or $selection -gt $sessions.Count) {
    Write-Host "Selección inválida." -ForegroundColor Red
    exit 1
}

# Sesión seleccionada:
$chosen            = $sessions[$selection - 1]
$sessionId         = [System.IO.Path]::GetFileNameWithoutExtension($chosen.Name)     # solo nombre, sin ruta
$sessionPathNoExt  = [System.IO.Path]::Combine($chosen.DirectoryName, $sessionId)    # ruta completa sin .rec

Write-Host ""
Write-Host ("Mostrando estado de la sesión: {0}" -f $sessionPathNoExt) -ForegroundColor Green
Write-Host ""

do {
    # Mostrar estado de la sesión (una sola llamada a john)
    $output = & $JohnExe "--status=$sessionPathNoExt" 2>&1

    # Buscar la línea de estado (empieza normalmente por "0g " o "1g ")
    $statusLine = $output | Where-Object { $_ -match '^\d+g ' } | Select-Object -Last 1

    if (-not $statusLine) {
        # Si por lo que sea no cuadra el patrón, usamos la última línea no vacía
        $statusLine = ($output | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -Last 1)
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host ("{0} - {1}" -f $timestamp, $statusLine)

    # Si el refresco es 0 o negativo, solo mostramos una vez
    if ($RefreshSeconds -le 0) {
        break
    }

    # Detectar si la sesión sigue activa (buscamos procesos john.exe cuyo CommandLine contenga el nombre de la sesión)
    $procs    = Get-CimInstance Win32_Process -Filter "Name = 'john.exe'" -ErrorAction SilentlyContinue
    $isActive = $false

    foreach ($p in $procs) {
        if ($p.CommandLine -and $p.CommandLine -like "*$sessionId*") {
            $isActive = $true
            break
        }
    }

    if (-not $isActive) {
        Write-Host ("{0} - La sesión ya no está activa (no hay procesos john.exe con ese nombre de sesión)." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")) -ForegroundColor Yellow
        break
    }

    Start-Sleep -Seconds $RefreshSeconds

} while ($true)
