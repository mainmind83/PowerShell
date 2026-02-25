<#
Este script está disponible bajo la licencia MIT.
Copyright (c) 2025 Kaizen Development Solutions.

Se permite el uso, copia, modificación y distribución del software
siempre que se mantenga este aviso de copyright y la referencia a la
licencia MIT. El software se proporciona "tal cual", sin garantías de
ningún tipo. Para más detalles consulte el archivo LICENSE del
repositorio.

.SYNOPSIS
    Desbloquea archivos eliminando la marca de seguridad (Zone.Identifier).

.DESCRIPTION
    Permite desbloquear cualquier tipo de archivo en una ruta específica.
    Puede trabajar sobre un único archivo o una carpeta completa.
    Soporta ejecución recursiva.

.PARAMETER Path
    Ruta del archivo o carpeta.

.PARAMETER Recurse
    Si se indica, procesa también subcarpetas.

.PARAMETER WhatIf
    Simula la ejecución sin aplicar cambios.

.EXAMPLE
    .\Desbloquear-Ficheros.ps1 -Path "C:\Descargas" -Recurse

.EXAMPLE
    .\Desbloquear-Ficheros.ps1 -Path "C:\Descargas\archivo.zip"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [switch]$Recurse
)

if (-not (Test-Path $Path)) {
    Write-Error "La ruta especificada no existe: $Path"
    exit 1
}

# Si es archivo individual
if ((Get-Item $Path).PSIsContainer -eq $false) {

    try {
        Unblock-File -Path $Path -ErrorAction Stop
        Write-Host "✔ Archivo desbloqueado: $Path" -ForegroundColor Green
    }
    catch {
        Write-Warning "No se pudo desbloquear: $Path"
    }

    return
}

# Si es carpeta
$files = Get-ChildItem -Path $Path -File -Recurse:$Recurse

if (-not $files) {
    Write-Host "No se encontraron archivos para procesar." -ForegroundColor Yellow
    return
}

foreach ($file in $files) {
    try {
        Unblock-File -Path $file.FullName -ErrorAction Stop
        Write-Host "✔ $($file.FullName)" -ForegroundColor Green
    }
    catch {
        Write-Warning "✖ Error en $($file.FullName)"
    }
}

Write-Host "`nProceso finalizado." -ForegroundColor Cyan
