<#
Este script está disponible bajo la licencia MIT.
Copyright (c) 2025 Kaizen Development Solutions.

Se permite el uso, copia, modificación y distribución del software
siempre que se mantenga este aviso de copyright y la referencia a la
licencia MIT. El software se proporciona "tal cual", sin garantías de
ningún tipo. Para más detalles consulte el archivo LICENSE del
repositorio.

.SYNOPSIS
Comprueba la IP pública de salida a Internet desde un puesto Windows
accediendo a distintos grupos de URLs, para diagnosticar escenarios
con múltiples conexiones a Internet.

.DESCRIPTION
El script realiza conexiones a una serie de URLs agrupadas por tipo
(administraciones públicas, eIDAS, factura electrónica, justicia, etc.)
y consulta un servicio externo para determinar la IP pública de salida.

Incluye barra de progreso, reintentos automáticos y notas explicativas
para servicios sensibles que pueden bloquear comprobaciones automáticas.

.NOTES
- El script NO fuerza rutas ni modifica configuración de red.
- Diseñado como herramienta de diagnóstico.
#>

# ================= CONFIGURACIÓN =================

$MaxRetries     = 3
$RetryDelaySec  = 3
$TimeoutSec     = 10
$CheckIPService = "https://api.ipify.org"

# Dominios sensibles que pueden bloquear pruebas automáticas
$SensitiveDomains = @(
    "izenpe.com"
)

# URLs agrupadas
$UrlGroups = @{
    "IZENPE" = @(
        "https://eidasbiz.izenpe.com",
        "https://eidas.izenpe.com",
        "https://eidas2.izenpe.com",
        "https://eidasbiz2.izenpe.com",
        "https://izenpe.com"
    )

    "Álava / Diputación" = @(
        "https://e-s.araba.eus",
        "https://apps.euskadi.eus",
        "https://araba.eus",
        "https://egoitza.araba.eus",
        "https://tae.araba.eus",
        "https://ticketbai.araba.eus",
        "https://web.araba.eus"
    )

    "Factura electrónica" = @(
        "https://efactura.coviran.es",
        "https://miacceso.e-factura.net"
    )

    "Servicios financieros" = @(
        "https://secure3.3etrade.com"
    )

    "Sede electrónica" = @(
        "https://www.sedelectronica.es",
        "https://peralta.sedelectronica.es"
    )

    "Justicia" = @(
        "https://sedejudicial.justicia.es",
        "https://www.justicia.es"
    )
}

# ================= FUNCIONES =================

function Get-SensitiveNote {
    param (
        [string]$Url
    )

    foreach ($Domain in $SensitiveDomains) {
        if ($Url -like "*$Domain*") {
            return "Servicio sensible: puede bloquear comprobaciones automáticas"
        }
    }
    return ""
}

# ================= EJECUCIÓN =================

$Results = @()
$AllUrls = ($UrlGroups.Values | ForEach-Object { $_ }).Count
$Current = 0

foreach ($Group in $UrlGroups.Keys) {
    foreach ($Url in $UrlGroups[$Group]) {

        $Current++
        $ProgressPercent = [int](($Current / $AllUrls) * 100)

        Write-Progress `
            -Activity "Comprobando IP de salida" `
            -Status "[$Current / $AllUrls] $Url" `
            -PercentComplete $ProgressPercent

        $Attempt = 0
        $Success = $false

        while (-not $Success -and $Attempt -lt $MaxRetries) {
            $Attempt++

            try {
                # Intento de conexión al destino
                Invoke-WebRequest -Uri $Url -Method Head -TimeoutSec $TimeoutSec -UseBasicParsing | Out-Null

                # Consulta de IP pública
                $PublicIP = Invoke-RestMethod -Uri $CheckIPService -TimeoutSec $TimeoutSec

                $Results += [PSCustomObject]@{
                    Grupo     = $Group
                    URL       = $Url
                    IP_Salida = $PublicIP.Trim()
                    Estado    = "OK"
                    Intento   = $Attempt
                    Nota      = (Get-SensitiveNote -Url $Url)
                    FechaHora = Get-Date
                }

                $Success = $true
            }
            catch {
                if ($Attempt -lt $MaxRetries) {
                    Start-Sleep -Seconds $RetryDelaySec
                }
                else {
                    $Results += [PSCustomObject]@{
                        Grupo     = $Group
                        URL       = $Url
                        IP_Salida = "N/A"
                        Estado    = "ERROR"
                        Intento   = $Attempt
                        Nota      = (Get-SensitiveNote -Url $Url)
                        FechaHora = Get-Date
                    }
                }
            }
        }
    }
}

Write-Progress -Activity "Comprobando IP de salida" -Completed

# ================= FIRMA FINAL =================

$Results += [PSCustomObject]@{
    Grupo     = "—"
    URL       = "www.kds.cloud"
    IP_Salida = "Kaizen Development Solutions"
    Estado    = "INFO"
    Intento   = "-"
    Nota      = ""
    FechaHora = Get-Date
}

# ================= RESULTADOS =================

$Results | Sort-Object Grupo, URL | Format-Table -AutoSize

# Exportar a CSV (opcional)
# $Results | Export-Csv ".\Resultado_IP_Salida.csv" -NoTypeInformation -Encoding UTF8
