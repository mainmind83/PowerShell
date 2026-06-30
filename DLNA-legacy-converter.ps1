<#
.SYNOPSIS
    DLNA-Legacy-Converter - prepara vídeo para reproducción directa (Direct Play)
    en renderers DLNA antiguos (TVs ~2012-2018: Samsung Tizen 2.x, LG webOS,
    Sony, Panasonic, etc.).

.DESCRIPTION
    Toma los ficheros .avi/.mkv/.mp4 de una carpeta y los deja listos para
    Direct Play en una TV DLNA antigua. Analiza CADA fichero con ffprobe y hace
    SOLO lo necesario (no reprocesa lo que ya está bien):

      - Plan "nada"   : ya es MP4 + H.264 (Level <= objetivo) + AAC -> NO se toca.
      - Plan "remux"  : es H.264 pero hay que ajustar algo sin recodificar vídeo:
                        reescribir el Level (5.1 -> 4.1), reencodear SOLO el audio
                        si no es AAC, y/o pasar el contenedor a MP4. Operación
                        casi instantánea y sin pérdida de vídeo.
      - Plan "recode" : el vídeo NO es H.264 (HEVC/AV1/VP9/MPEG-2...). Se
                        recodifica a H.264 (escala a <=1080p, High@Level, 8-bit,
                        AAC). Esto SÍ es lento y con pérdida. Con -SinRecodificar
                        estos ficheros se omiten en vez de recodificarse.

    Por qué estas correcciones:
      - NIVEL H.264: muchos 1080p vienen marcados como "Level 5.1" (anómalo).
        Jellyfin lo cree "demasiado" para TVs antiguas y TRANSCODIFICA (rompe el
        seek y carga CPU). Reescribir la etiqueta a 4.1 permite Direct Play.
      - TIMESTAMPS: el AVI no guarda marcas por frame; al remuxear se declara el
        frame rate y se generan PTS para que no haya saltos ni desincronía.
      - CONTENEDOR: MP4 con '+faststart' (índice al principio -> seek por red).
      - AUDIO: se estandariza a AAC. Si el origen ya es AAC se copia tal cual
        (sin pérdida); si no (MP3, AC3, etc.), se reencodea a AAC 192k.

    Por qué AAC y no, p.ej., dejar MP3:
      DLNA admite MP3 como códec de audio en general, PERO los PERFILES de vídeo
      DLNA (H.264 dentro de MP4) definen AAC como el audio esperado para Direct
      Play. Muchas TVs reproducen H.264+MP3 en MP4 igualmente (van más allá del
      perfil base), así que para una TV concreta MP3 puede bastar. AAC es la
      opción CANÓNICA y más portable: la acepta cualquier renderer que se ciña
      al perfil de vídeo, evitando que algún cliente estricto transcodifique el
      audio. Por eso el script estandariza a AAC por defecto; no es obligatorio
      para toda TV, es la apuesta segura. (Ref.: perfiles DLNA AVC_MP4_*_AAC; el
      soporte nativo típico de TVs es MP4 + H.264 + AAC.)

    Idempotente: al re-ejecutar, los que ya cumplen se saltan ("ya cumple"). Si
    origen y destino son la misma carpeta, los .mp4 se reprocesan in-place de
    forma segura (se escribe a un temporal y se reemplaza solo si todo va bien).

    El encoder de recodificación se autodetecta según la GPU del equipo y se
    PRUEBA de verdad antes de usarlo: NVENC (Nvidia) > AMF (AMD) > QSV (Intel) >
    libx264 (software). Si la GPU no responde, cae al siguiente.

.PARAMETER Origen
    Carpeta con los .avi.
    Precedencia: este parámetro > variable $src del script > se pregunta por teclado.

.PARAMETER Destino
    Carpeta de salida para los .mp4.
    Precedencia: este parámetro > variable $dst del script > se pregunta
    (con sugerencia <Origen>\MP4).

.PARAMETER Fps
    Frame rate a asumir si no se puede detectar del fichero. Por defecto 25.

.PARAMETER Level
    Nivel H.264 a forzar en la etiqueta. Por defecto "4.1".

.PARAMETER Sobrescribir
    Si se indica, regenera ficheros .mp4 que ya existan en Destino.
    Por defecto los salta (permite reanudar una tanda interrumpida).

.PARAMETER SinRecodificar
    Si se indica, los ficheros que NO sean H.264 se OMITEN (con aviso) en lugar
    de recodificarse. Útil cuando solo quieres el remux rápido sin tandas largas.

.EXAMPLE
    .\DLNA-Legacy-Converter.ps1
    Convierte los .avi de la carpeta del script a una subcarpeta "MP4".

.EXAMPLE
    .\DLNA-Legacy-Converter.ps1 -Origen "\\192.168.1.100\media\AVI" -Destino "\\192.168.1.100\media\MP4"

.EXAMPLE
    .\DLNA-Legacy-Converter.ps1 -Origen "D:\descargas\completados"
    Salida en "D:\descargas\completados\MP4".

.NOTES
    Requiere ffmpeg y ffprobe. Si no están, el script intenta instalarlos con
    winget (paquete Gyan.FFmpeg) y localizarlos automáticamente.

    Licencia MIT - Copyright (c) 2025 Fernando Zabalza · www.mainmind.com
    Parte del repositorio github.com/mainmind83/PowerShell (ver fichero LICENSE).
#>

[CmdletBinding()]
param(
    [string]$Origen,
    [string]$Destino,
    [string]$Fps = "25",
    [string]$Level = "4.1",
    [switch]$Sobrescribir,
    [switch]$SinRecodificar
)

# ============================================================================
#  RUTAS FIJAS (opcional)
#  Rellena estas variables para no tener que pasar parámetros cada vez.
#  Precedencia: parámetro -Origen/-Destino  >  estas variables  >  se preguntan.
#  Déjalas en "" (vacías, como están) para pasarlas por parámetro o que las pida.
#  Ejemplo de formato (carpeta compartida en red):
#     $src = "\\192.168.1.100\media\AVI"
#     $dst = "\\192.168.1.100\media\MP4"
# ============================================================================
$src = ""
$dst = ""
# ============================================================================

# Acentos y caja Unicode correctos en consola
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ----------------------------------------------------------------------------
function Show-Banner {
    $c = "Cyan"
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor $c
    Write-Host "     DLNA-Legacy-Converter   ( AVI / MKV / MP4  ->  MP4 )" -ForegroundColor $c
    Write-Host "  ------------------------------------------------------------" -ForegroundColor $c
    Write-Host "     video : H.264 (copy si ya lo es) - Level 4.1" -ForegroundColor $c
    Write-Host "     audio : AAC 192k (stereo)" -ForegroundColor $c
    Write-Host "     mp4   : +faststart (seek por red)" -ForegroundColor $c
    Write-Host "     extra : recodifica incompatibles con GPU (auto)" -ForegroundColor $c
    Write-Host "  ============================================================" -ForegroundColor $c
    Write-Host ""
}

# ----------------------------------------------------------------------------
# Localiza un ejecutable: PATH primero, luego rutas típicas de winget.
function Resolve-Tool([string]$name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\$name.exe")
    )
    $pkgRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path $pkgRoot) {
        $hit = Get-ChildItem -Path $pkgRoot -Recurse -Filter "$name.exe" -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($hit) { $candidates += $hit.FullName }
    }
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    return $null
}

# Asegura ffmpeg + ffprobe. Si faltan, intenta instalarlos con winget.
# Devuelve un objeto con las rutas, o lanza error si no es posible.
function Ensure-Ffmpeg {
    $ff = Resolve-Tool "ffmpeg"
    $fp = Resolve-Tool "ffprobe"
    if ($ff -and $fp) {
        Write-Host "  [OK] ffmpeg encontrado:  $ff"  -ForegroundColor Green
        Write-Host "  [OK] ffprobe encontrado: $fp" -ForegroundColor Green
        return [pscustomobject]@{ ffmpeg = $ff; ffprobe = $fp }
    }

    Write-Host "  [!] ffmpeg/ffprobe no encontrados. Intentando instalar con winget..." -ForegroundColor Yellow
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "No se encontró ffmpeg ni winget. Instala manualmente:`n    winget install Gyan.FFmpeg"
    }

    & winget install --id Gyan.FFmpeg -e --source winget `
        --accept-package-agreements --accept-source-agreements | Out-Host

    # Tras instalar, el PATH de ESTA sesión no se refresca: añadimos la carpeta
    # de enlaces de winget para esta ejecución.
    $links = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"
    if ((Test-Path $links) -and ($env:Path -notlike "*$links*")) {
        $env:Path = "$links;$env:Path"
    }

    $ff = Resolve-Tool "ffmpeg"
    $fp = Resolve-Tool "ffprobe"
    if (-not ($ff -and $fp)) {
        throw "ffmpeg se instaló pero no se localiza en esta sesión. Cierra y reabre PowerShell y vuelve a ejecutar."
    }
    Write-Host "  [OK] ffmpeg instalado: $ff" -ForegroundColor Green
    return [pscustomobject]@{ ffmpeg = $ff; ffprobe = $fp }
}

# Duración en segundos (o $null)
function Get-Dur([string]$exe, [string]$file) {
    $d = & $exe -v error -show_entries format=duration -of csv=p=0 -- "$file"
    if ($d) { return [double]$d } else { return $null }
}

# Analiza un fichero (AVI/MKV/MP4) y decide QUÉ hay que hacer para que reproduzca
# por Direct Play en una TV DLNA antigua (H.264 <=Level dado, AAC, MP4, faststart).
# Hace SOLO lo necesario: no recodifica de más ni reprocesa lo que ya cumple.
#
# Devuelve: Video, Audio, Alto, Level (int), Ext, Plan, Motivo
#   Plan = "nada"   -> ya cumple (MP4 + H.264 + Level<=objetivo + AAC): no se toca.
#   Plan = "remux"  -> H.264 pero hay que arreglar algo SIN recodificar vídeo:
#                      reescribir Level, reencodear solo audio, y/o pasar a MP4.
#   Plan = "recode" -> vídeo NO es H.264 (HEVC/AV1/VP9/MPEG-2/...): hay que recodificar.
function Get-PlanConversion([string]$exe, [string]$file, [int]$lvlObjetivo) {
    $vcodec = ("" + (& $exe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 -- $file)).Trim()
    $height = ("" + (& $exe -v error -select_streams v:0 -show_entries stream=height     -of csv=p=0 -- $file)).Trim()
    $lvlRaw = ("" + (& $exe -v error -select_streams v:0 -show_entries stream=level      -of csv=p=0 -- $file)).Trim()
    $acodec = ("" + (& $exe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 -- $file)).Trim()

    [int]$h = 0;   [void][int]::TryParse($height, [ref]$h)
    [int]$lvl = 0; [void][int]::TryParse($lvlRaw, [ref]$lvl)   # 41=L4.1, 51=L5.1; 0 o <0 = desconocido
    $ext = ([System.IO.Path]::GetExtension($file)).ToLower()

    # Vídeo no H.264 -> recodificar (copy no lo arregla)
    if ($vcodec -ne "h264") {
        return [pscustomobject]@{
            Video=$vcodec; Audio=$acodec; Alto=$h; Level=$lvl; Ext=$ext
            Plan="recode"; Motivo="vídeo '$vcodec' no es H.264"
        }
    }

    # H.264: ver qué hay que tocar (sin recodificar vídeo)
    $faltaMp4   = ($ext -ne ".mp4")
    $faltaLevel = ($lvl -gt $lvlObjetivo)            # solo si se conoce y es mayor
    # Audio: se estandariza a AAC. DLNA admite MP3 como códec, pero el PERFIL de
    # vídeo (H.264/MP4) espera AAC para Direct Play. MP3 suele reproducir en
    # muchas TVs, pero AAC es la opción canónica y portable (ver cabecera).
    $faltaAudio = ($acodec -ne "aac")
    $aviso1080  = ($h -gt 1080)                      # informativo (no fuerza nada aquí)

    if (-not ($faltaMp4 -or $faltaLevel -or $faltaAudio)) {
        $m = if ($aviso1080) { "ya cumple, pero ${h}p (>1080p): verifica en la TV" } else { "ya cumple" }
        return [pscustomobject]@{
            Video=$vcodec; Audio=$acodec; Alto=$h; Level=$lvl; Ext=$ext
            Plan="nada"; Motivo=$m
        }
    }

    $det = @()
    if ($faltaMp4)   { $det += "contenedor $ext->mp4" }
    if ($faltaLevel) { $det += "Level $lvl->$lvlObjetivo" }
    if ($faltaAudio) { $det += "audio $acodec->aac" }
    return [pscustomobject]@{
        Video=$vcodec; Audio=$acodec; Alto=$h; Level=$lvl; Ext=$ext
        Plan="remux"; Motivo=($det -join ", ")
    }
}

# Devuelve los argumentos de vídeo de ffmpeg para un encoder dado.
function Get-EncoderArgs([string]$enc, [string]$lvl) {
    switch ($enc) {
        "h264_nvenc" { return @("-c:v","h264_nvenc","-preset","p5","-rc","vbr","-cq","23","-b:v","0") }
        "h264_amf"   { return @("-c:v","h264_amf","-quality","balanced","-rc","cqp","-qp_i","22","-qp_p","22") }
        "h264_qsv"   { return @("-c:v","h264_qsv","-global_quality","23") }
        default      { return @("-c:v","libx264","-preset","veryfast","-crf","20") }
    }
}

# Detecta el mejor encoder H.264 disponible y lo PRUEBA de verdad (no basta con
# que ffmpeg lo liste: un build puede listar h264_amf sin GPU AMD presente).
# Orden de preferencia segun la GPU real del equipo: NVENC > AMF > QSV > libx264.
function Select-VideoEncoder([string]$ffmpeg) {
    # GPUs presentes (por nombre)
    $gpu = ""
    try { $gpu = (Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object -Expand Name) -join " " } catch {}
    $gpu = $gpu.ToLower()

    # Encoders que ffmpeg dice tener
    $have = (& $ffmpeg -hide_banner -encoders 2>&1) -join "`n"

    # Candidatos ordenados por GPU detectada + soporte en ffmpeg
    $cand = @()
    if (($gpu -match "nvidia|geforce|rtx|gtx") -and ($have -match "h264_nvenc")) { $cand += "h264_nvenc" }
    if (($gpu -match "amd|radeon|rx ")        -and ($have -match "h264_amf"))   { $cand += "h264_amf" }
    if (($gpu -match "intel")                 -and ($have -match "h264_qsv"))   { $cand += "h264_qsv" }
    $cand += "libx264"   # software, siempre como ultimo recurso

    foreach ($enc in $cand) {
        # Test real: codifica unos frames de una fuente sintetica a /dev/null
        $vargs = Get-EncoderArgs $enc $Level
        $test = @("-hide_banner","-loglevel","error","-y",
                  "-f","lavfi","-i","color=c=black:s=320x240:r=25","-frames:v","8") + $vargs + @("-f","null","-")
        & $ffmpeg @test 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $enc
        }
        Write-Host ("  [enc] $enc no funciona en este equipo, probando siguiente...") -ForegroundColor DarkGray
    }
    return "libx264"
}

# ============================================================================
Show-Banner

# ---- Resolver ORIGEN: parámetro > variable $src > preguntar ----
if (-not $Origen) {
    if ($src -and $src.Trim()) {
        $Origen = $src
        Write-Host "  Origen tomado de la variable \$src del script." -ForegroundColor DarkGray
    }
    else {
        $sugerido = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
        $resp = Read-Host "  Carpeta de ORIGEN (.avi) [Enter = $sugerido]"
        $Origen = if ($resp.Trim()) { $resp.Trim() } else { $sugerido }
    }
}

# ---- Resolver DESTINO: parámetro > variable $dst > preguntar (Enter = <Origen>\MP4) ----
if (-not $Destino) {
    if ($dst -and $dst.Trim()) {
        $Destino = $dst
        Write-Host "  Destino tomado de la variable \$dst del script." -ForegroundColor DarkGray
    }
    else {
        $sugeridoDst = Join-Path $Origen "MP4"
        $resp = Read-Host "  Carpeta de DESTINO (.mp4) [Enter = $sugeridoDst]"
        $Destino = if ($resp.Trim()) { $resp.Trim() } else { $sugeridoDst }
    }
}

if (-not (Test-Path -LiteralPath $Origen)) {
    Write-Error "La carpeta de origen no existe: $Origen"; return
}

Write-Host "  Origen : $Origen"
Write-Host "  Destino: $Destino"
Write-Host ""

# Herramientas
$tools = Ensure-Ffmpeg
$FFMPEG  = $tools.ffmpeg
$FFPROBE = $tools.ffprobe
Write-Host ""

# Crear destino
New-Item -ItemType Directory -Force -Path $Destino | Out-Null

# Nivel objetivo en forma numérica (4.1 -> 41) para comparar con ffprobe
[int]$LVLOBJ = 41
[void][int]::TryParse(($Level -replace '\.',''), [ref]$LVLOBJ)

# Listar entradas: AVI, MKV y MP4 (no recursivo: ignora subcarpetas como Destino)
$avis = Get-ChildItem -LiteralPath $Origen -File |
        Where-Object { $_.Extension.ToLower() -in @('.avi','.mkv','.mp4') } |
        Sort-Object Name
if (-not $avis) { Write-Warning "No hay ficheros .avi/.mkv/.mp4 en $Origen"; return }
Write-Host ("  Encontrados {0} ficheros (avi/mkv/mp4)`n" -f $avis.Count) -ForegroundColor Cyan

# Encoder para recodificar los que NO son H.264. Se detecta una sola vez.
$ENC = $null
if (-not $SinRecodificar) {
    Write-Host "  Detectando encoder de vídeo (para recodificar incompatibles)..." -ForegroundColor DarkGray
    $ENC = Select-VideoEncoder $FFMPEG
    $tipo = if ($ENC -eq "libx264") { "software (CPU)" } else { "hardware/GPU" }
    Write-Host ("  Encoder de recodificación: {0}  [{1}]" -f $ENC, $tipo) -ForegroundColor Cyan
    Write-Host ""
}

$ok = 0; $fallo = 0; $saltados = 0; $incompat = 0; $recod = 0; $yacumple = 0

foreach ($f in $avis) {
    $in  = $f.FullName
    $out = Join-Path $Destino ($f.BaseName + ".mp4")
    $esMismoFichero = ($in -eq $out)   # entrada .mp4 que coincide con su propia salida

    Write-Host (">> {0}" -f $f.Name) -ForegroundColor Cyan

    # --- Analizar el fichero y decidir el plan (nada / remux / recode) ---
    $p = Get-PlanConversion $FFPROBE $in $LVLOBJ

    # Ya cumple: H.264, Level OK, AAC y MP4. No se toca.
    if ($p.Plan -eq "nada") {
        Write-Host ("   {0} (H.264 L{1}, audio {2})" -f $p.Motivo, $p.Level, $p.Audio) -ForegroundColor DarkGreen
        $yacumple++; continue
    }

    # Si NO es el propio fichero y ya hay un MP4 con ese nombre en destino, no se regenera.
    if ((Test-Path -LiteralPath $out) -and -not $Sobrescribir -and -not $esMismoFichero) {
        Write-Host ("   {0}" -f $p.Motivo) -ForegroundColor DarkGray
        Write-Host "     ya hay un MP4 con ese nombre en destino, no se regenera (usa -Sobrescribir para forzar)" -ForegroundColor DarkGray
        $saltados++; continue
    }

    # Recodificación (vídeo no H.264)
    if ($p.Plan -eq "recode" -and $SinRecodificar) {
        Write-Host ("   [X] no es H.264 ({0}): omitido (-SinRecodificar activo)" -f $p.Video) -ForegroundColor Red
        $incompat++; continue
    }

    # Escribir SIEMPRE a un temporal y reemplazar al final: evita corromper el
    # original si ffmpeg falla, y permite reprocesar in-place (origen == destino).
    $tmp = Join-Path $Destino ($f.BaseName + ".__tmp__.mp4")

    if ($p.Plan -eq "recode") {
        Write-Host ("   [X] no es H.264 ({0}): se RECODIFICA con {1} (lento/con pérdida; escala a <=1080p)" -f $p.Video, $ENC) -ForegroundColor Yellow
        $encArgs = Get-EncoderArgs $ENC $Level
        $ffArgs  = @("-hide_banner","-loglevel","error","-y","-i",$in,
                     "-map","0:v:0","-map","0:a:0",
                     "-vf","scale=-2:'min(1080,ih)'") +
                   $encArgs +
                   @("-profile:v","high","-level",$Level,"-pix_fmt","yuv420p",
                     "-c:a","aac","-b:a","192k","-movflags","+faststart","--",$tmp)
        & $FFMPEG @ffArgs
        $accion = "recode"
    }
    else {
        # remux: vídeo copy (+ Level reescrito), audio copy si ya es AAC, MP4 + faststart
        Write-Host ("   se ajusta sin recodificar vídeo: {0}" -f $p.Motivo) -ForegroundColor Yellow
        if ($p.Audio -eq "aac") { $audioArgs = @("-c:a","copy") }
        else                    { $audioArgs = @("-c:a","aac","-b:a","192k") }

        $fpsRaw = & $FFPROBE -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 -- $in
        if (-not $fpsRaw -or $fpsRaw -eq "0/0") { $fpsRaw = $Fps }

        $ffArgs = @("-hide_banner","-loglevel","error","-y","-r",$fpsRaw,"-i",$in,
                    "-map","0:v:0","-map","0:a:0",
                    "-c:v","copy","-bsf:v","h264_metadata=level=$Level") +
                  $audioArgs +
                  @("-movflags","+faststart","-fflags","+genpts","--",$tmp)
        & $FFMPEG @ffArgs
        $accion = "remux"
    }

    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tmp)) {
        Write-Warning "   ffmpeg falló, no se generó el MP4 (el original queda intacto)"
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        $fallo++; continue
    }

    # Verificación de duración (detecta truncados por corte de red)
    $da = Get-Dur $FFPROBE $in
    $dm = Get-Dur $FFPROBE $tmp
    if ($da -and $dm -and ([math]::Abs($da - $dm) -lt 1.5)) {
        # Sustituir el destino por el temporal ya validado
        Move-Item -LiteralPath $tmp -Destination $out -Force
        if ($accion -eq "recode") {
            Write-Host ("   OK recodificado  ({0:N0}s)" -f $dm) -ForegroundColor Green
            $recod++
        } else {
            Write-Host ("   OK ajustado  ({0:N0}s)" -f $dm) -ForegroundColor Green
            $ok++
        }
    } else {
        Write-Warning ("   duración no cuadra (in={0} out={1}) - se descarta, original intacto" -f $da, $dm)
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        $fallo++
    }
}

Write-Host ""
Write-Host "  ---------------------------------------------" -ForegroundColor Cyan
Write-Host ("  Resumen:  {0} ya cumplían   {1} ajustados   {2} recodificados   {3} saltados   {4} con problemas" -f $yacumple, $ok, $recod, $saltados, $fallo) -ForegroundColor Cyan
Write-Host "  ---------------------------------------------" -ForegroundColor Cyan
if ($incompat -gt 0) {
    Write-Host ("  {0} fichero(s) NO H.264 omitidos (-SinRecodificar activo)." -f $incompat) -ForegroundColor Red
}
Write-Host ""
Write-Host "  Siguiente: reescanea la biblioteca y valida 1-2 episodios en la TV" -ForegroundColor DarkGray
Write-Host "  (reproduce + salta al final: comprueba seek y sincronía de audio)." -ForegroundColor DarkGray
Write-Host ""
