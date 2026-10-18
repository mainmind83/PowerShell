<#
.SYNOPSIS
    NTLM Check: diagnostica por que Windows bloquea el acceso SMB a un recurso compartido
    tras el endurecimiento NTLMv1 de la actualizacion de octubre de 2026 (KB5127648).
    NTLM Check: diagnoses why Windows blocks SMB access to a file share after the
    NTLMv1 hardening shipped in the October 2026 update (KB5127648).

.DESCRIPTION
    ES: Script de diagnostico de SOLO LECTURA y bilingue (espanol/ingles). No cambia nada. Ver README.md.
    EN: READ-ONLY, bilingual (Spanish/English) diagnostic script. It changes nothing. See README.md.

.PARAMETER Target
    Servidor o recurso compartido: FQDN, IP o ruta UNC (\\servidor\recurso).
    Si no se indica, se pide de forma interactiva.
    Server or file share: FQDN, IP or UNC path (\\server\share). Asked interactively if omitted.

.PARAMETER Lang
    es | en. Si no se indica, se detecta el idioma de Windows y se ofrece elegir.
    es | en. If omitted, the Windows language is detected and a choice is offered.

.PARAMETER Days
    Dias de historico de eventos NTLM a revisar (1-90). Por defecto 7.
    Days of NTLM event history to review (1-90). Default 7.

.EXAMPLE
    .\Test-NtlmHardening.ps1
.EXAMPLE
    .\Test-NtlmHardening.ps1 -Target \\nas.midominio.local\datos -Lang es
.EXAMPLE
    .\Test-NtlmHardening.ps1 -Target 192.168.1.20 -Lang en -Days 2

.LINK
    https://support.microsoft.com/help/5066470
.LINK
    https://aka.ms/ntlmlogandblock
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Target,
    [ValidateSet('es', 'en')]
    [string]$Lang,
    [ValidateRange(1, 90)]
    [int]$Days = 7
)

$ErrorActionPreference = 'Stop'
$ScriptVersion  = '1.0.0'
$AffectedBuilds = @(26100, 26200, 26300)   # Windows 11 24H2 / 25H2 / 26H2, Server 2025
$OctoberUbr     = 9711                     # KB5127648 (2026-10-13)
$KbUrl          = 'https://support.microsoft.com/help/5066470'

# ---------------------------------------------------------------------------
# Textos / Strings
# ---------------------------------------------------------------------------
$Strings = @{
  es = @{
    Subtitle      = 'Diagnóstico de bloqueos NTLM/SMB (KB5127648 · KB5066470)'
    ReadOnly      = 'Solo lectura: este script no modifica nada'
    NotAdmin      = 'No se está ejecutando como administrador: algunos registros de eventos pueden no ser legibles'
    AskTarget     = 'Servidor o recurso compartido (FQDN, IP o \\servidor\recurso)'
    TargetEmpty   = 'Indica un servidor: no se puede diagnosticar sin destino'
    TargetBad     = '"{0}" no es un FQDN, una IP ni una ruta UNC válidos'
    TargetParamBad = 'El valor de -Target no es válido: {0}'
    S1            = '1. Destino: {0}'
    S1Name        = '1. Destino'
    KindFqdn      = 'Nombre DNS completo (FQDN)'
    KindShort     = 'Nombre corto (sin dominio)'
    KindIp        = 'Dirección IP'
    ShortWarn     = 'Nombre corto: depende del sufijo DNS. Si falla, prueba con el FQDN'
    IpInfo        = 'Con una IP, Windows nunca usa Kerberos: la autenticación será siempre NTLM'
    Share         = 'Recurso: {0}'
    DnsOk         = 'Resuelve a {0}'
    DnsFail       = 'No resuelve en DNS: {0}'
    DnsFailS      = 'No resuelve'
    TcpOk         = 'Puerto TCP 445 abierto en {0}'
    TcpOkS        = '445 abierto ({0})'
    TcpFail       = 'El puerto TCP 445 no responde: problema de red, DNS, VPN o cortafuegos, no de NTLM'
    TcpFailS      = '445 sin respuesta'
    S2            = '2. Versión de Windows'
    S2Name        = '2. Windows'
    BuildOct      = '{0}: incluye la acumulativa de octubre de 2026 o posterior'
    BuildOld      = '{0}: anterior a octubre de 2026 (el cambio llegará con la próxima acumulativa)'
    BuildOut      = '{0}: fuera del alcance de KB5066470'
    KbInstalled   = 'KB5127648 instalada el {0}'
    S3            = '3. Credential Guard'
    S3Name        = '3. Credential Guard'
    CgRunning     = 'En ejecución (evento 13 de Wininit en este arranque)'
    CgRunningWmi  = 'En ejecución (WMI Win32_DeviceGuard)'
    CgRunningS    = 'En ejecución'
    CgWmiFalse    = 'WMI no lo refleja (SecurityServicesRunning sin 1): falso negativo, la fuente fiable es el evento 13'
    CgFailed      = 'Configurado pero no arrancó (eventos de Wininit {0} en este arranque)'
    CgFailedS     = 'No arrancó'
    CgOff         = 'No está en ejecución: el endurecimiento NTLMv1 de KB5066470 sí se aplica a este equipo'
    CgOffS        = 'Desactivado'
    CgConfig      = 'Configuración: directiva VBS={0}, directiva LsaCfgFlags={1}, Lsa\LsaCfgFlags={2}, Scenarios\CredentialGuard\Enabled={3}'
    VbsPolicyOff  = 'La seguridad basada en virtualización está DESHABILITADA por directiva (habitual en guías de rendimiento para juegos)'
    ScenResidue   = 'Scenarios\CredentialGuard\Enabled = 0 es un resto de configuración: la directiva lo anula y se puede borrar'
    Hvci          = 'Integridad de memoria (HVCI): {0}'
    HvciOn        = 'en ejecución'
    HvciOff       = 'no en ejecución (independiente de Credential Guard)'
    S4            = '4. BlockNtlmv1SSO (KB5066470)'
    S4Name        = '4. BlockNtlmv1SSO'
    BlkCg         = 'No aplica: Credential Guard ya protege las credenciales derivadas de NTLMv1 (valor: {0})'
    BlkCgS        = 'No aplica (CG)'
    BlkCgRedund   = 'BlockNtlmv1SSO = 0 es innecesario con Credential Guard activo: se puede borrar'
    BlkEnforce    = 'Sin definir = Enforce por defecto: puede bloquear SMB con credenciales explícitas (evento 4015)'
    BlkEnforceS   = 'Enforce (defecto)'
    BlkAudit      = 'Sin definir = Audit por defecto en esta build'
    BlkAuditS     = 'Audit (defecto)'
    BlkZero       = '0 = Audit forzado: excepción manual que afecta a todo el equipo; Microsoft la plantea como temporal'
    BlkZeroS      = 'Audit (forzado)'
    BlkOne        = '1 = Enforce explícito'
    BlkOneS       = 'Enforce (explícito)'
    BlkOther      = 'Valor no documentado: {0}'
    S5            = '5. Nivel de autenticación de LAN Manager'
    S5Name        = '5. LmCompatibilityLevel'
    LmDefault     = 'Sin definir = 3: el cliente solo envía NTLMv2'
    LmLow         = '{0}: el cliente puede enviar LM/NTLMv1'
    LmOk          = '{0}: el cliente solo envía NTLMv2'
    S6            = '6. Cliente SMB: bloqueo de NTLM'
    S6Name        = '6. SMB BlockNTLM'
    SmbNA         = 'No disponible en esta versión de Windows'
    SmbOn         = 'ACTIVADO (local={0}, directiva={1}). Excepciones: {2}'
    SmbOnS        = 'Activado'
    SmbNotExc     = 'El destino NO está en la lista de excepciones'
    SmbExc        = 'El destino está en la lista de excepciones'
    SmbOff        = 'Desactivado (local={0}, directiva={1})'
    SmbOffS       = 'Desactivado'
    S7            = '7. Restricción de NTLM saliente (LSA)'
    S7Name        = '7. RestrictSendingNTLM'
    RsDeny        = '2 = Denegar todo. Servidores permitidos: {0}'
    RsDenyS       = 'Denegar todo'
    RsAudit       = '1 = Solo auditoría'
    RsAuditS      = 'Auditoría'
    RsOff         = 'Sin restricción (RestrictSendingNTLMTraffic = {0})'
    RsOffS        = 'Sin restricción'
    S8            = '8. Eventos NTLM hacia el destino (últimos {0} días)'
    S8Name        = '8. Eventos NTLM'
    EvNone        = 'Ningún evento 4015/4020 hacia el destino'
    EvNoneS       = 'Sin eventos'
    EvV1          = 'Se negoció {0} el {1}: el servidor o el cliente aceptan NTLMv1'
    EvBlocked     = '{0} bloqueo(s) (evento 4015), el último el {1}, sin autenticación correcta posterior'
    EvBlockedS    = 'Bloqueado'
    EvOk          = 'Última autenticación correcta: {0} el {1} (evento 4020)'
    EvOkFixed     = 'Hubo {0} bloqueo(s) anteriores: ya resuelto'
    S9            = '9. Sesión SMB activa'
    S9Name        = '9. Sesión SMB'
    SessNone      = 'No hay ninguna sesión SMB abierta con el destino'
    SessNoneS     = 'Sin sesión'
    SessOk        = '{0}  dialecto {1}, usuario {2}, firmada={3}, cifrada={4}'
    SessCache     = 'Una sesión abierta no vuelve a autenticarse: para probar de verdad, desconecta (net use \\{0} /delete) y reconecta'
    Summary       = 'Resumen'
    Diagnosis     = 'Diagnóstico'
    NextTitle     = 'Siguientes pasos:'
    DxNet         = 'El fallo es de red, no de NTLM: revisa DNS, la VPN y el cortafuegos hasta que el puerto 445 responda.'
    DxKb          = 'Causa probable: el endurecimiento NTLMv1 de KB5127648 (BlockNtlmv1SSO en Enforce por defecto) con Credential Guard desactivado.'
    DxSmb         = 'Causa probable: el bloqueo NTLM del cliente SMB, sin excepción para este servidor.'
    DxRs          = 'Causa probable: la restricción de NTLM saliente de LSA (Denegar todo), sin excepción para este servidor.'
    DxV1          = 'Causa probable: se está usando NTLMv1, que Windows ya no admite.'
    DxUnknown     = 'Hay bloqueos registrados, pero ninguna configuración local los explica. Revisa Microsoft-Windows-SMBClient/Security.'
    DxOk          = 'No se detectan bloqueos NTLM hacia este destino.'
    DxRisk        = 'Este equipo es vulnerable al bloqueo de KB5127648 aunque ahora no haya fallos registrados.'
    NsCg          = 'Recomendado: activa Credential Guard (gpedit.msc > Plantillas administrativas > Sistema > Device Guard > Activar la seguridad basada en la virtualización > Credential Guard "Habilitado sin bloqueo UEFI"). Puedes dejar la integridad de código deshabilitada si te da problemas con drivers o juegos.'
    NsCgVbs       = 'Para eso, quita primero el "Deshabilitada" de esa misma directiva: ahora mismo impide cualquier servicio de VBS.'
    NsBlk0        = 'Alternativa si Credential Guard no es viable: BlockNtlmv1SSO = 0 en HKLM\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0. Afecta a todo el equipo y es temporal: documéntalo como decisión.'
    NsReboot      = 'Reinicia, desconecta la unidad o sesión existente y vuelve a conectar para que se autentique de nuevo.'
    NsSmbExc      = 'Añade el servidor a las excepciones: Set-SmbClientConfiguration -BlockNTLMServerExceptionList "{0}" (o en la directiva de LanmanWorkstation si viene de ahí).'
    NsRsExc       = 'Añade el servidor en "Seguridad de red: restringir NTLM: agregar excepciones de servidor remoto para la autenticación NTLM".'
    NsLm          = 'Sube el nivel de autenticación de LAN Manager a "Enviar solo respuesta NTLMv2 y rechazar LM y NTLM" (LmCompatibilityLevel = 5).'
    NsServerV2    = 'En el servidor, permite solo NTLMv2 y SMB 2/3 como mínimo.'
    NsRetest      = 'Vuelve a ejecutar este script después de cada cambio.'
    Reference     = 'Referencia: {0}'
    ResultFail    = 'Resultado: {0} fallo(s), {1} aviso(s).'
    ResultWarn    = 'Resultado: sin fallos, {0} aviso(s).'
    ResultOk      = 'Resultado: todo correcto.'
    Yes           = 'sí'
    No            = 'no'
    NotSet        = '(no existe)'
    Empty         = '(vacía)'
  }
  en = @{
    Subtitle      = 'NTLM/SMB block diagnostics (KB5127648 · KB5066470)'
    ReadOnly      = 'Read-only: this script changes nothing'
    NotAdmin      = 'Not running as administrator: some event logs may not be readable'
    AskTarget     = 'Server or file share (FQDN, IP or \\server\share)'
    TargetEmpty   = 'Enter a server: diagnostics need a target'
    TargetBad     = '"{0}" is not a valid FQDN, IP or UNC path'
    TargetParamBad = 'Invalid -Target value: {0}'
    S1            = '1. Target: {0}'
    S1Name        = '1. Target'
    KindFqdn      = 'Fully qualified DNS name (FQDN)'
    KindShort     = 'Short name (no domain)'
    KindIp        = 'IP address'
    ShortWarn     = 'Short name: depends on the DNS suffix. If it fails, try the FQDN'
    IpInfo        = 'With an IP address Windows never uses Kerberos: authentication will always be NTLM'
    Share         = 'Share: {0}'
    DnsOk         = 'Resolves to {0}'
    DnsFail       = 'Does not resolve in DNS: {0}'
    DnsFailS      = 'Does not resolve'
    TcpOk         = 'TCP port 445 open on {0}'
    TcpOkS        = '445 open ({0})'
    TcpFail       = 'TCP port 445 does not answer: network, DNS, VPN or firewall issue, not NTLM'
    TcpFailS      = '445 no answer'
    S2            = '2. Windows version'
    S2Name        = '2. Windows'
    BuildOct      = '{0}: includes the October 2026 cumulative update or later'
    BuildOld      = '{0}: older than October 2026 (the change arrives with the next cumulative update)'
    BuildOut      = '{0}: outside the scope of KB5066470'
    KbInstalled   = 'KB5127648 installed on {0}'
    S3            = '3. Credential Guard'
    S3Name        = '3. Credential Guard'
    CgRunning     = 'Running (Wininit event 13 in this boot)'
    CgRunningWmi  = 'Running (WMI Win32_DeviceGuard)'
    CgRunningS    = 'Running'
    CgWmiFalse    = 'WMI does not show it (SecurityServicesRunning without 1): false negative, event 13 is the reliable source'
    CgFailed      = 'Configured but failed to start (Wininit events {0} in this boot)'
    CgFailedS     = 'Failed to start'
    CgOff         = 'Not running: the KB5066470 NTLMv1 hardening does apply to this computer'
    CgOffS        = 'Off'
    CgConfig      = 'Configuration: policy VBS={0}, policy LsaCfgFlags={1}, Lsa\LsaCfgFlags={2}, Scenarios\CredentialGuard\Enabled={3}'
    VbsPolicyOff  = 'Virtualization-based security is DISABLED by policy (common in gaming performance guides)'
    ScenResidue   = 'Scenarios\CredentialGuard\Enabled = 0 is a leftover: the policy overrides it and it can be deleted'
    Hvci          = 'Memory integrity (HVCI): {0}'
    HvciOn        = 'running'
    HvciOff       = 'not running (independent of Credential Guard)'
    S4            = '4. BlockNtlmv1SSO (KB5066470)'
    S4Name        = '4. BlockNtlmv1SSO'
    BlkCg         = 'Not applicable: Credential Guard already protects NTLMv1-derived credentials (value: {0})'
    BlkCgS        = 'N/A (CG)'
    BlkCgRedund   = 'BlockNtlmv1SSO = 0 is unnecessary with Credential Guard running: it can be deleted'
    BlkEnforce    = 'Not set = Enforce by default: it can block SMB with explicit credentials (event 4015)'
    BlkEnforceS   = 'Enforce (default)'
    BlkAudit      = 'Not set = Audit by default on this build'
    BlkAuditS     = 'Audit (default)'
    BlkZero       = '0 = forced Audit: a manual, machine-wide exception that Microsoft frames as temporary'
    BlkZeroS      = 'Audit (forced)'
    BlkOne        = '1 = explicit Enforce'
    BlkOneS       = 'Enforce (explicit)'
    BlkOther      = 'Undocumented value: {0}'
    S5            = '5. LAN Manager authentication level'
    S5Name        = '5. LmCompatibilityLevel'
    LmDefault     = 'Not set = 3: the client only sends NTLMv2'
    LmLow         = '{0}: the client may send LM/NTLMv1'
    LmOk          = '{0}: the client only sends NTLMv2'
    S6            = '6. SMB client: NTLM blocking'
    S6Name        = '6. SMB BlockNTLM'
    SmbNA         = 'Not available on this Windows version'
    SmbOn         = 'ENABLED (local={0}, policy={1}). Exceptions: {2}'
    SmbOnS        = 'Enabled'
    SmbNotExc     = 'The target is NOT in the exception list'
    SmbExc        = 'The target is in the exception list'
    SmbOff        = 'Disabled (local={0}, policy={1})'
    SmbOffS       = 'Disabled'
    S7            = '7. Outgoing NTLM restriction (LSA)'
    S7Name        = '7. RestrictSendingNTLM'
    RsDeny        = '2 = Deny all. Allowed servers: {0}'
    RsDenyS       = 'Deny all'
    RsAudit       = '1 = Audit only'
    RsAuditS      = 'Audit'
    RsOff         = 'No restriction (RestrictSendingNTLMTraffic = {0})'
    RsOffS        = 'No restriction'
    S8            = '8. NTLM events towards the target (last {0} days)'
    S8Name        = '8. NTLM events'
    EvNone        = 'No 4015/4020 events towards the target'
    EvNoneS       = 'No events'
    EvV1          = '{0} negotiated on {1}: the server or the client accepts NTLMv1'
    EvBlocked     = '{0} block(s) (event 4015), the last on {1}, with no successful authentication afterwards'
    EvBlockedS    = 'Blocked'
    EvOk          = 'Last successful authentication: {0} on {1} (event 4020)'
    EvOkFixed     = 'There were {0} earlier block(s): already solved'
    S9            = '9. Active SMB session'
    S9Name        = '9. SMB session'
    SessNone      = 'No SMB session open with the target'
    SessNoneS     = 'No session'
    SessOk        = '{0}  dialect {1}, user {2}, signed={3}, encrypted={4}'
    SessCache     = 'An open session does not re-authenticate: to test for real, disconnect (net use \\{0} /delete) and reconnect'
    Summary       = 'Summary'
    Diagnosis     = 'Diagnosis'
    NextTitle     = 'Next steps:'
    DxNet         = 'This is a network failure, not NTLM: check DNS, the VPN and the firewall until port 445 answers.'
    DxKb          = 'Likely cause: the KB5127648 NTLMv1 hardening (BlockNtlmv1SSO in Enforce by default) with Credential Guard off.'
    DxSmb         = 'Likely cause: SMB client NTLM blocking, with no exception for this server.'
    DxRs          = 'Likely cause: the LSA outgoing NTLM restriction (Deny all), with no exception for this server.'
    DxV1          = 'Likely cause: NTLMv1 is in use, which Windows no longer accepts.'
    DxUnknown     = 'Blocks are logged, but no local setting explains them. Check Microsoft-Windows-SMBClient/Security.'
    DxOk          = 'No NTLM blocks detected towards this target.'
    DxRisk        = 'This computer is exposed to the KB5127648 block even though no failures are logged right now.'
    NsCg          = 'Recommended: enable Credential Guard (gpedit.msc > Administrative Templates > System > Device Guard > Turn On Virtualization Based Security > Credential Guard "Enabled without UEFI lock"). You can leave code integrity disabled if it causes trouble with drivers or games.'
    NsCgVbs       = 'To do that, first remove the "Disabled" setting from that same policy: right now it prevents every VBS service.'
    NsBlk0        = 'Fallback if Credential Guard is not viable: BlockNtlmv1SSO = 0 in HKLM\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0. It is machine-wide and temporary: document it as a decision.'
    NsReboot      = 'Reboot, disconnect the existing drive or session and reconnect so it authenticates again.'
    NsSmbExc      = 'Add the server to the exceptions: Set-SmbClientConfiguration -BlockNTLMServerExceptionList "{0}" (or in the LanmanWorkstation policy if it comes from there).'
    NsRsExc       = 'Add the server to "Network security: Restrict NTLM: Add remote server exceptions for NTLM authentication".'
    NsLm          = 'Raise the LAN Manager authentication level to "Send NTLMv2 response only. Refuse LM & NTLM" (LmCompatibilityLevel = 5).'
    NsServerV2    = 'On the server, allow NTLMv2 only and SMB 2/3 as the minimum.'
    NsRetest      = 'Run this script again after each change.'
    Reference     = 'Reference: {0}'
    ResultFail    = 'Result: {0} failure(s), {1} warning(s).'
    ResultWarn    = 'Result: no failures, {0} warning(s).'
    ResultOk      = 'Result: all good.'
    Yes           = 'yes'
    No            = 'no'
    NotSet        = '(not set)'
    Empty         = '(empty)'
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
 _   _ _____ _     __  __    ____ _               _
| \ | |_   _| |   |  \/  |  / ___| |__   ___  ___| | __
|  \| | | | | |   | |\/| | | |   | '_ \ / _ \/ __| |/ /
| |\  | | | | |___| |  | | | |___| | | |  __/ (__|   <
|_| \_| |_| |_____|_|  |_|  \____|_| |_|\___|\___|_|\_\
'@
Write-Host ''
Write-Host $banner -ForegroundColor DarkYellow
Write-Host ('{0,56}' -f "by mainmind.com  ·  v$ScriptVersion") -ForegroundColor Gray
Write-Host ('  ' + ('-' * 60)) -ForegroundColor DarkGray
Write-Host "  $(T Subtitle)" -ForegroundColor Gray
Write-Host "  $(T ReadOnly)" -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# Utilidades / Helpers
# ---------------------------------------------------------------------------
$Summary = [System.Collections.Generic.List[object]]::new()
function Add-Result([string]$Step, [ValidateSet('OK', 'WARN', 'FAIL', 'INFO')][string]$State, [string]$Detail) {
    $Summary.Add([pscustomobject]@{ Step = $Step; State = $State; Detail = $Detail })
}
function Write-Step($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "    [OK]   $msg" -ForegroundColor Green }
function Write-Info($msg)  { Write-Host "    [i]    $msg" -ForegroundColor Gray }
function Write-Warn2($msg) { Write-Host "    [!]    $msg" -ForegroundColor Yellow }
function Write-Fail($msg)  { Write-Host "    [X]    $msg" -ForegroundColor Red }

function Get-RegValue([string]$Path, [string]$Name) {
    try { (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { $null }
}
function Format-Value($Value) {
    if ($null -eq $Value) { return (T NotSet) }
    if ($Value -is [array]) {
        if ($Value.Count -eq 0) { return (T Empty) }
        return ($Value -join ', ')
    }
    return [string]$Value
}
function Format-Bool($Value) {
    if ($null -eq $Value) { return '?' }
    if ($Value) { T Yes } else { T No }
}

# Normaliza la entrada: \\servidor\recurso, //servidor/recurso, smb://servidor/recurso, [IPv6]
# Normalizes input: \\server\share, //server/share, smb://server/share, [IPv6]
function ConvertFrom-TargetInput([string]$Text) {
    $t = $Text.Trim().Trim('"').Trim("'")
    $share = $null
    if ($t -match '^(?:\\\\|//|smb://)([^\\/]+)(?:[\\/]+([^\\/]+))?') {
        $t = $Matches[1]
        if ($Matches.Count -gt 2 -and $Matches[2]) { $share = $Matches[2] }
    }
    if ($t -match '^\[(.+)\]$') { $t = $Matches[1] }
    $t = $t.TrimEnd('.')

    $kind = $null
    $ip = $null
    if ($t -match '^\d{1,3}(\.\d{1,3}){3}$') {
        if ([System.Net.IPAddress]::TryParse($t, [ref]$ip)) { $kind = 'IP' }
    }
    elseif ($t.Contains(':')) {
        if ([System.Net.IPAddress]::TryParse($t, [ref]$ip)) { $kind = 'IP' }
    }
    elseif ($t -notmatch '^[\d.]+$' -and
            $t -match '^(?=.{1,253}$)(?!-)[A-Za-z0-9_-]{1,63}(?<!-)(\.(?!-)[A-Za-z0-9_-]{1,63}(?<!-))*$') {
        $kind = if ($t.Contains('.')) { 'FQDN' } else { 'Short' }
    }
    if (-not $kind) { return $null }
    [pscustomobject]@{ Host = $t.ToLower(); Share = $share; Kind = $kind }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host ''; Write-Warn2 (T NotAdmin) }

$lsaPath   = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
$msv10Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0'
$os        = Get-CimInstance -ClassName Win32_OperatingSystem
$bootTime  = $os.LastBootUpTime

# ---------------------------------------------------------------------------
# 1. Destino / Target
# ---------------------------------------------------------------------------
$tgt = $null
if ($Target) {
    $tgt = ConvertFrom-TargetInput $Target
    if (-not $tgt) { throw (T TargetParamBad $Target) }
}
else {
    Write-Host ''
    while (-not $tgt) {
        $raw = Read-Host "  $(T AskTarget)"
        if ([string]::IsNullOrWhiteSpace($raw)) { Write-Warn2 (T TargetEmpty); continue }
        $tgt = ConvertFrom-TargetInput $raw
        if (-not $tgt) { Write-Warn2 (T TargetBad $raw.Trim()) }
    }
}

Write-Step (T S1 $tgt.Host)
switch ($tgt.Kind) {
    'FQDN'  { Write-Info (T KindFqdn) }
    'Short' { Write-Warn2 (T ShortWarn) }
    'IP'    { Write-Info (T KindIp); Write-Info (T IpInfo) }
}
if ($tgt.Share) { Write-Info (T Share $tgt.Share) }

$addresses = @()
$dnsOk = $true
if ($tgt.Kind -eq 'IP') {
    $addresses = @($tgt.Host)
}
else {
    try {
        $addresses = @([System.Net.Dns]::GetHostAddresses($tgt.Host) |
                       Where-Object { $_.AddressFamily -in 'InterNetwork', 'InterNetworkV6' } |
                       ForEach-Object { $_.IPAddressToString })
        Write-Ok (T DnsOk ($addresses -join ', '))
    }
    catch {
        $dnsOk = $false
        $ex = $_.Exception
        while ($ex.InnerException) { $ex = $ex.InnerException }
        Write-Fail (T DnsFail $ex.Message)
    }
}

$tcpOk = $false
if ($dnsOk) {
    $tcp = Test-NetConnection -ComputerName $tgt.Host -Port 445 -WarningAction SilentlyContinue
    $tcpOk = [bool]$tcp.TcpTestSucceeded
    if ($tcpOk) {
        Write-Ok (T TcpOk $tcp.RemoteAddress)
        Add-Result (T S1Name) 'OK' (T TcpOkS $tcp.RemoteAddress)
    }
    else {
        Write-Fail (T TcpFail)
        Add-Result (T S1Name) 'FAIL' (T TcpFailS)
    }
}
else {
    Add-Result (T S1Name) 'FAIL' (T DnsFailS)
}

# Nombres con los que el destino puede aparecer en los eventos / Names the target may use in events
$matchNames = @($tgt.Host) + $addresses
if ($tgt.Kind -ne 'IP') { $matchNames += $tgt.Host.Split('.')[0] }
$matchNames = @($matchNames | Where-Object { $_ } | ForEach-Object { $_.ToLower() } | Select-Object -Unique)

# ---------------------------------------------------------------------------
# 2. Versión de Windows / Windows version
# ---------------------------------------------------------------------------
Write-Step (T S2)
$cvPath  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$build   = [int](Get-RegValue $cvPath 'CurrentBuild')
$ubr     = [int](Get-RegValue $cvPath 'UBR')
$display = Get-RegValue $cvPath 'DisplayVersion'
$product = $os.Caption   # ProductName sigue diciendo "Windows 10" en Windows 11 / still says "Windows 10" on Windows 11
$buildText = '{0} {1} ({2}.{3})' -f $product, $display, $build, $ubr

$enforceByDefault = $false
if ($AffectedBuilds -contains $build) {
    if ($ubr -ge $OctoberUbr) {
        $enforceByDefault = $true
        Write-Info (T BuildOct $buildText)
    }
    else { Write-Info (T BuildOld $buildText) }
}
else { Write-Info (T BuildOut $buildText) }
Add-Result (T S2Name) 'INFO' ('{0}.{1}' -f $build, $ubr)

$kb = Get-HotFix -Id 'KB5127648' -ErrorAction SilentlyContinue
if ($kb -and $kb.InstalledOn) { Write-Info (T KbInstalled ('{0:dd/MM/yyyy}' -f $kb.InstalledOn)) }

# ---------------------------------------------------------------------------
# 3. Credential Guard
# ---------------------------------------------------------------------------
Write-Step (T S3)
$wininit = @(Get-WinEvent -FilterHashtable @{
        LogName = 'System'; ProviderName = 'Microsoft-Windows-Wininit'; StartTime = $bootTime.AddSeconds(-30)
    } -ErrorAction SilentlyContinue)
$cgEvent  = @($wininit | Where-Object { $_.Id -eq 13 }).Count -gt 0
$cgErrors = @($wininit | Where-Object { $_.Id -in 15, 16, 17 })

$dg = $null
try { $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop } catch { }
$wmiCg   = [bool]($dg -and (@($dg.SecurityServicesRunning) -contains 1))
$wmiHvci = [bool]($dg -and (@($dg.SecurityServicesRunning) -contains 2))
$cgRunning = $cgEvent -or $wmiCg

if ($cgRunning) {
    if ($cgEvent) { Write-Ok (T CgRunning) } else { Write-Ok (T CgRunningWmi) }
    if ($cgEvent -and -not $wmiCg) { Write-Info (T CgWmiFalse) }
    Add-Result (T S3Name) 'OK' (T CgRunningS)
}
elseif ($cgErrors.Count -gt 0) {
    Write-Fail (T CgFailed (($cgErrors | Select-Object -ExpandProperty Id -Unique) -join ', '))
    Add-Result (T S3Name) 'FAIL' (T CgFailedS)
}
else {
    Write-Warn2 (T CgOff)
    Add-Result (T S3Name) 'WARN' (T CgOffS)
}

$polVbs = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard' 'EnableVirtualizationBasedSecurity'
$polCg  = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard' 'LsaCfgFlags'
$lsaCg  = Get-RegValue $lsaPath 'LsaCfgFlags'
$scenCg = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard' 'Enabled'
Write-Info (T CgConfig (Format-Value $polVbs) (Format-Value $polCg) (Format-Value $lsaCg) (Format-Value $scenCg))
$vbsPolicyOff = ($polVbs -eq 0)
if ($vbsPolicyOff) { Write-Warn2 (T VbsPolicyOff) }
if ($scenCg -eq 0 -and $polCg -in 1, 2) { Write-Info (T ScenResidue) }
if ($dg) { Write-Info (T Hvci $(if ($wmiHvci) { T HvciOn } else { T HvciOff })) }

# ---------------------------------------------------------------------------
# 4. BlockNtlmv1SSO (KB5066470)
# ---------------------------------------------------------------------------
Write-Step (T S4)
$blockV1 = Get-RegValue $msv10Path 'BlockNtlmv1SSO'
$kbEnforcing = $false
if ($cgRunning) {
    Write-Ok (T BlkCg (Format-Value $blockV1))
    if ($blockV1 -eq 0) { Write-Warn2 (T BlkCgRedund) }
    Add-Result (T S4Name) 'OK' (T BlkCgS)
}
elseif ($null -eq $blockV1) {
    if ($enforceByDefault) {
        $kbEnforcing = $true
        Write-Warn2 (T BlkEnforce)
        Add-Result (T S4Name) 'WARN' (T BlkEnforceS)
    }
    else {
        Write-Info (T BlkAudit)
        Add-Result (T S4Name) 'INFO' (T BlkAuditS)
    }
}
elseif ($blockV1 -eq 0) {
    Write-Warn2 (T BlkZero)
    Add-Result (T S4Name) 'WARN' (T BlkZeroS)
}
elseif ($blockV1 -eq 1) {
    $kbEnforcing = $true
    Write-Info (T BlkOne)
    Add-Result (T S4Name) 'INFO' (T BlkOneS)
}
else {
    Write-Warn2 (T BlkOther $blockV1)
    Add-Result (T S4Name) 'WARN' ([string]$blockV1)
}

# ---------------------------------------------------------------------------
# 5. LmCompatibilityLevel
# ---------------------------------------------------------------------------
Write-Step (T S5)
$lm = Get-RegValue $lsaPath 'LmCompatibilityLevel'
$lmLow = $false
if ($null -eq $lm) {
    Write-Ok (T LmDefault)
    Add-Result (T S5Name) 'OK' '3'
}
elseif ($lm -le 2) {
    $lmLow = $true
    Write-Fail (T LmLow $lm)
    Add-Result (T S5Name) 'FAIL' ([string]$lm)
}
else {
    Write-Ok (T LmOk $lm)
    Add-Result (T S5Name) 'OK' ([string]$lm)
}

# ---------------------------------------------------------------------------
# 6. Cliente SMB: BlockNTLM / SMB client: BlockNTLM
# ---------------------------------------------------------------------------
Write-Step (T S6)
$smbPolicy = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation' 'BlockNTLM'
$smbLocal  = $null
$smbExc    = @()
try {
    $smbCfg = Get-SmbClientConfiguration -ErrorAction Stop
    $props  = $smbCfg.PSObject.Properties.Name
    if ($props -contains 'BlockNTLM') { $smbLocal = $smbCfg.BlockNTLM }
    if ($props -contains 'BlockNTLMServerExceptionList') { $smbExc = @($smbCfg.BlockNTLMServerExceptionList | Where-Object { $_ }) }
}
catch { }

$smbBlocking = $false
if ($null -eq $smbLocal -and $null -eq $smbPolicy) {
    Write-Info (T SmbNA)
    Add-Result (T S6Name) 'INFO' (T SmbNA)
}
elseif ($smbLocal -eq $true -or $smbPolicy -eq 1) {
    Write-Warn2 (T SmbOn (Format-Value $smbLocal) (Format-Value $smbPolicy) (Format-Value $smbExc))
    $inExc = [bool]($smbExc | Where-Object { $matchNames -contains $_.ToLower() })
    if ($inExc) {
        Write-Ok (T SmbExc)
        Add-Result (T S6Name) 'OK' (T SmbOnS)
    }
    else {
        $smbBlocking = $true
        Write-Fail (T SmbNotExc)
        Add-Result (T S6Name) 'FAIL' (T SmbOnS)
    }
}
else {
    Write-Ok (T SmbOff (Format-Value $smbLocal) (Format-Value $smbPolicy))
    Add-Result (T S6Name) 'OK' (T SmbOffS)
}

# ---------------------------------------------------------------------------
# 7. RestrictSendingNTLMTraffic
# ---------------------------------------------------------------------------
Write-Step (T S7)
$restrict = Get-RegValue $msv10Path 'RestrictSendingNTLMTraffic'
$allowed  = @(Get-RegValue $msv10Path 'ClientAllowedNTLMServers' | Where-Object { $_ })
$rsBlocking = $false
switch ($restrict) {
    2 {
        Write-Warn2 (T RsDeny (Format-Value $allowed))
        $allowedHit = [bool]($allowed | Where-Object { $p = $_.ToLower(); $matchNames | Where-Object { $_ -like $p -or $p -like "*$_*" } })
        if ($allowedHit) { Add-Result (T S7Name) 'OK' (T RsDenyS) }
        else { $rsBlocking = $true; Add-Result (T S7Name) 'FAIL' (T RsDenyS) }
    }
    1 {
        Write-Info (T RsAudit)
        Add-Result (T S7Name) 'INFO' (T RsAuditS)
    }
    default {
        Write-Ok (T RsOff (Format-Value $restrict))
        Add-Result (T S7Name) 'OK' (T RsOffS)
    }
}

# ---------------------------------------------------------------------------
# 8. Eventos NTLM / NTLM events
# ---------------------------------------------------------------------------
Write-Step (T S8 $Days)
$events = @(Get-WinEvent -FilterHashtable @{
        LogName = 'Microsoft-Windows-NTLM/Operational'; Id = 4015, 4020; StartTime = (Get-Date).AddDays(-$Days)
    } -ErrorAction SilentlyContinue)

function Get-EventField([string]$Message, [string]$Pattern) {
    if (-not $Message) { return $null }
    $m = [regex]::Match($Message, $Pattern, 'Multiline')
    if ($m.Success) { $m.Groups[1].Value.Trim() } else { $null }
}
function Test-EventTarget([string]$Message) {
    $res = Get-EventField $Message '^\s*(?:Target server|Target Resource):\s*(\S+)'
    $ip  = Get-EventField $Message '^\s*Target IP:\s*(\S+)'
    $candidates = @()
    if ($res) {
        $h = ($res -replace '^[^/]+/', '').ToLower()
        $candidates += $h
        $candidates += $h.Split('.')[0]
    }
    if ($ip) { $candidates += $ip.ToLower() }
    return [bool]($candidates | Where-Object { $matchNames -contains $_ })
}

$tgtEvents = @($events | Where-Object { Test-EventTarget $_.Message } | ForEach-Object {
        [pscustomobject]@{
            Time    = $_.TimeCreated
            Id      = $_.Id
            Version = Get-EventField $_.Message 'NTLM Version:\s*(\S+)'
        }
    })

$evBlocked = $false
$evV1      = $false
$blocks    = @($tgtEvents | Where-Object { $_.Id -eq 4015 })
$lastBlock = $blocks | Sort-Object Time -Descending | Select-Object -First 1
$lastUse   = $tgtEvents | Where-Object { $_.Id -eq 4020 } | Sort-Object Time -Descending | Select-Object -First 1

if ($tgtEvents.Count -eq 0) {
    Write-Info (T EvNone)
    Add-Result (T S8Name) 'INFO' (T EvNoneS)
}
elseif ($lastUse -and $lastUse.Version -match 'NTLMv1|^LM') {
    $evV1 = $true
    Write-Fail (T EvV1 $lastUse.Version ('{0:dd/MM HH:mm}' -f $lastUse.Time))
    Add-Result (T S8Name) 'FAIL' $lastUse.Version
}
elseif ($lastBlock -and (-not $lastUse -or $lastBlock.Time -gt $lastUse.Time)) {
    $evBlocked = $true
    Write-Fail (T EvBlocked $blocks.Count ('{0:dd/MM HH:mm}' -f $lastBlock.Time))
    Add-Result (T S8Name) 'FAIL' (T EvBlockedS)
}
else {
    $ver = if ($lastUse.Version) { $lastUse.Version } else { 'NTLM' }
    Write-Ok (T EvOk $ver ('{0:dd/MM HH:mm}' -f $lastUse.Time))
    if ($blocks.Count -gt 0) { Write-Info (T EvOkFixed $blocks.Count) }
    Add-Result (T S8Name) 'OK' ('{0} {1:dd/MM HH:mm}' -f $ver, $lastUse.Time)
}

# ---------------------------------------------------------------------------
# 9. Sesión SMB activa / Active SMB session
# ---------------------------------------------------------------------------
Write-Step (T S9)
$sessions = @()
try {
    $sessions = @(Get-SmbConnection -ErrorAction Stop | Where-Object {
            $s = $_.ServerName.ToLower()
            ($matchNames -contains $s) -or ($matchNames -contains $s.Split('.')[0])
        })
}
catch { }

if ($sessions.Count -eq 0) {
    Write-Info (T SessNone)
    Add-Result (T S9Name) 'INFO' (T SessNoneS)
}
else {
    foreach ($s in $sessions) {
        $p = $s.PSObject.Properties.Name
        $signed    = if ($p -contains 'Signed')    { $s.Signed }    else { $null }
        $encrypted = if ($p -contains 'Encrypted') { $s.Encrypted } else { $null }
        Write-Ok (T SessOk ('\\{0}\{1}' -f $s.ServerName, $s.ShareName) $s.Dialect $s.UserName (Format-Bool $signed) (Format-Bool $encrypted))
    }
    Write-Info (T SessCache $tgt.Host)
    $dialects = ($sessions | Select-Object -ExpandProperty Dialect -Unique) -join ', '
    Add-Result (T S9Name) 'OK' ('{0} ({1})' -f $sessions.Count, $dialects)
}

# ---------------------------------------------------------------------------
# Resumen / Summary
# ---------------------------------------------------------------------------
$stateText  = @{ OK = 'OK'; WARN = '[!]'; FAIL = '[X]'; INFO = '[i]' }
$stateColor = @{ OK = 'Green'; WARN = 'Yellow'; FAIL = 'Red'; INFO = 'Gray' }

Write-Host "`n  $(T Summary)" -ForegroundColor Cyan
Write-Host ('  ' + ('-' * 60)) -ForegroundColor DarkGray
foreach ($r in $Summary) {
    Write-Host ('  {0,-26} {1,-5} {2}' -f $r.Step, $stateText[$r.State], $r.Detail) -ForegroundColor $stateColor[$r.State]
}

# ---------------------------------------------------------------------------
# Diagnóstico y siguientes pasos / Diagnosis and next steps
# ---------------------------------------------------------------------------
$dx   = @()
$next = @()
if (-not $dnsOk -or -not $tcpOk) {
    $dx += T DxNet
}
else {
    if ($evV1 -or $lmLow) {
        $dx += T DxV1
        if ($lmLow) { $next += T NsLm }
        $next += T NsServerV2
    }
    if ($smbBlocking) {
        $dx += T DxSmb
        $next += T NsSmbExc $tgt.Host
    }
    if ($rsBlocking) {
        $dx += T DxRs
        $next += T NsRsExc
    }
    if ($evBlocked -and $kbEnforcing -and -not $smbBlocking -and -not $rsBlocking) {
        $dx += T DxKb
    }
    if ($kbEnforcing -and -not $cgRunning) {
        if (-not $evBlocked) { $dx += T DxRisk }
        $next += T NsCg
        if ($vbsPolicyOff) { $next += T NsCgVbs }
        $next += T NsBlk0
    }
    if ($evBlocked -and $dx.Count -eq 0) { $dx += T DxUnknown }
    if ($dx.Count -eq 0) { $dx += T DxOk }
    if ($next.Count -gt 0) { $next += T NsReboot }
}

Write-Host "`n  $(T Diagnosis)" -ForegroundColor Cyan
Write-Host ('  ' + ('-' * 60)) -ForegroundColor DarkGray
foreach ($d in $dx) { Write-Host "  $d" }

if ($next.Count -gt 0) {
    Write-Host "`n  $(T NextTitle)" -ForegroundColor Cyan
    for ($i = 0; $i -lt $next.Count; $i++) { Write-Host ("    {0}. {1}" -f ($i + 1), $next[$i]) }
    Write-Host ("    {0}. {1}" -f ($next.Count + 1), (T NsRetest))
}

$fails = @($Summary | Where-Object { $_.State -eq 'FAIL' }).Count
$warns = @($Summary | Where-Object { $_.State -eq 'WARN' }).Count
Write-Host ''
if ($fails -gt 0)     { Write-Host "  $(T ResultFail $fails $warns)" -ForegroundColor Red }
elseif ($warns -gt 0) { Write-Host "  $(T ResultWarn $warns)" -ForegroundColor Yellow }
else                  { Write-Host "  $(T ResultOk)" -ForegroundColor Green }
Write-Host "  $(T Reference $KbUrl)" -ForegroundColor DarkGray
Write-Host ''

if ($fails -gt 0) { exit 1 }
exit 0
