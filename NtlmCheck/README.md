# NTLM Check

**Test-NtlmHardening.ps1 · v1.0.0 · by [mainmind.com](https://mainmind.com)**

🇪🇸 Español · [🇬🇧 English](README.en.md)

Script de diagnóstico para Windows que explica por qué el equipo ya no puede conectar a un recurso compartido SMB (un NAS, un Samba o un equipo fuera de dominio) con el error:

> Error de autenticación porque la autenticación NTLM está deshabilitada

Está pensado para el cambio que trae la **actualización acumulativa de octubre de 2026 (KB5127648)**, pero revisa también el resto de configuraciones que producen el mismo mensaje. Es de **solo lectura**: no modifica el registro, las directivas ni ningún servicio.

## El problema

Desde la acumulativa del 13 de octubre de 2026 (**KB5127648**, builds `26100.9711`, `26200.9711` y `26300.9711`), Windows 11 24H2, 25H2 y 26H2 y Windows Server 2025 cambian el comportamiento por defecto de `BlockNtlmv1SSO` de *Audit* a *Enforce* cuando ese valor no existe en el registro **y Credential Guard está desactivado** ([KB5066470](https://support.microsoft.com/help/5066470)).

Microsoft lo documenta como un cambio que puede afectar a Wi-Fi, Ethernet y VPN con MS-CHAPv2. En la práctica también rompe el acceso SMB con credenciales explícitas a servidores fuera de dominio, **aunque cliente y servidor negocien NTLMv2**. Las pistas:

- El evento **4015** en `Microsoft-Windows-NTLM/Operational`, con proceso `SYSTEM` (PID 4) y destino `cifs/<servidor>`.
- `Get-SmbClientConfiguration` muestra `BlockNTLM = False`, así que el bloqueo **no** viene del cliente SMB.
- Funcionaba hasta instalar la actualización.

## Requisitos

- Windows 10/11 o Windows Server con PowerShell 5.1 o superior
- Recomendado: ejecutarlo como administrador (sin privilegios algunos registros de eventos pueden no ser legibles)

## Descarga

```powershell
New-Item -ItemType Directory -Path C:\mainmind\NtlmCheck -Force | Out-Null
Invoke-WebRequest https://raw.githubusercontent.com/mainmind83/PowerShell/main/NtlmCheck/Test-NtlmHardening.ps1 -OutFile C:\mainmind\NtlmCheck\Test-NtlmHardening.ps1
Unblock-File C:\mainmind\NtlmCheck\Test-NtlmHardening.ps1
```

Antes de ejecutar un script descargado de internet, léelo.

## Uso

```powershell
cd C:\mainmind\NtlmCheck
powershell -ExecutionPolicy Bypass -File .\Test-NtlmHardening.ps1
```

Si no se indica el destino, el script lo pide y lo valida: acepta un FQDN, una IP (v4 o v6) o una ruta UNC, y vuelve a preguntar si la entrada no es válida.

| Parámetro | Descripción |
|---|---|
| `-Target <destino>` | Servidor o recurso compartido: `nas.midominio.local`, `192.168.1.20` o `\\nas.midominio.local\datos`. También admite `//servidor/recurso` y `smb://servidor/recurso`. |
| `-Lang es\|en` | Idioma de los mensajes. Si no se indica, detecta el idioma de Windows y pregunta (Enter acepta el detectado). |
| `-Days <1-90>` | Días de histórico de eventos NTLM que se revisan. Por defecto 7. |

Código de salida: `0` si no hay fallos y `1` si los hay, para poder usarlo desde un RMM con `-Target` y `-Lang` (así no hace ninguna pregunta).

## Qué comprueba, paso a paso

1. **Destino.** Valida la entrada, avisa si es un nombre corto (depende del sufijo DNS) o una IP (Windows nunca usa Kerberos contra una IP), resuelve el nombre y prueba el puerto TCP 445. Si falla aquí, el problema es de red, DNS, VPN o cortafuegos, no de NTLM.
2. **Versión de Windows.** Build y UBR, y si ya incluye la acumulativa de octubre de 2026. Indica la fecha de instalación de KB5127648 si aparece.
3. **Credential Guard.** Si está en ejecución en el arranque actual, según el **evento 13 de Wininit**. No se fía solo de WMI: `Win32_DeviceGuard.SecurityServicesRunning` puede dar un falso `0` con Credential Guard funcionando. Muestra de dónde sale la configuración (directiva, `Lsa\LsaCfgFlags`, `Scenarios\CredentialGuard`) y avisa si la seguridad basada en virtualización está **deshabilitada por directiva** o si quedan restos de herramientas de optimización.
4. **BlockNtlmv1SSO.** El modo efectivo: *Enforce* por defecto, *Audit* forzado (`0`), *Enforce* explícito (`1`) o "no aplica" si Credential Guard está activo.
5. **Nivel de autenticación de LAN Manager** (`LmCompatibilityLevel`). Falla si el cliente puede enviar LM/NTLMv1.
6. **Bloqueo NTLM del cliente SMB** (`BlockNTLM`, local y por directiva) y si el destino está en la lista de excepciones.
7. **Restricción de NTLM saliente de LSA** (`RestrictSendingNTLMTraffic`) y sus excepciones.
8. **Eventos NTLM hacia el destino.** Cruza los eventos **4015** (bloqueos) y **4020** (autenticaciones, con la versión negociada) de los últimos días. Distingue entre "bloqueado ahora" y "hubo bloqueos, pero ya hay una autenticación correcta posterior".
9. **Sesión SMB activa.** Dialecto, usuario, firma y cifrado. Recuerda que una sesión ya abierta no vuelve a autenticarse, así que no sirve para probar un cambio.

Al final muestra un **resumen**, un **diagnóstico con la causa probable** y unos **siguientes pasos calculados según lo encontrado**.

## Cómo solucionarlo

Por orden de preferencia:

1. **Activar Credential Guard.** Es lo que recomienda Microsoft y el cambio de KB5066470 no se aplica cuando está activo. En `gpedit.msc` → *Plantillas administrativas* → *Sistema* → *Device Guard* → *Activar la seguridad basada en la virtualización*: **Habilitada**, nivel *Arranque seguro*, Credential Guard **Habilitado sin bloqueo UEFI**. La *protección de integridad de código* (HVCI) es independiente: si te da problemas con drivers o con el anti-cheat de algún juego, puedes dejarla deshabilitada y seguir teniendo Credential Guard.
2. **`BlockNtlmv1SSO = 0`** en `HKLM\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0`, solo si Credential Guard no es viable. Devuelve a **todo el equipo** el comportamiento anterior al endurecimiento y Microsoft lo plantea como temporal: documéntalo como decisión, no como solución.

En ambos casos: reinicia, desconecta la unidad o sesión existente y vuelve a conectar para que se autentique de nuevo. Después vuelve a ejecutar el script.

Lo que **no** soluciona este caso: `Set-SmbClientConfiguration -BlockNTLM $false` (ya está en `False`), activar el acceso de invitado inseguro o bajar el nivel de LAN Manager. Esto último empeora la seguridad y además no sirve.

Del lado del servidor, aprovecha para exigir **solo NTLMv2** y **SMB 2/3 como mínimo**.

## Limitaciones conocidas

- Lee los eventos en el formato en que Windows los escribe, que en las versiones probadas está en inglés aunque el sistema esté en español. Si un evento no se puede interpretar, se ignora en lugar de dar un falso positivo.
- La detección de la acumulativa de octubre usa la build y el UBR (`.9711`). Una acumulativa posterior también cumple la condición.
- Si el destino se indica por IP y Windows registró los bloqueos con el nombre (o al revés), el paso 8 puede no relacionarlos. En ese caso, prueba con la misma forma con la que conectas.
- La relación entre `BlockNtlmv1SSO` y el acceso SMB con NTLMv2 es una observación práctica, no algo documentado por Microsoft.

## Referencias

- [KB5066470 · Cambios en NTLMv1 en Windows 11 24H2 y Windows Server 2025](https://support.microsoft.com/help/5066470)
- [KB5127648 · Acumulativa de octubre de 2026](https://support.microsoft.com/help/5127648)
- [Registro y bloqueo de NTLM](https://aka.ms/ntlmlogandblock)
- [Credential Guard](https://learn.microsoft.com/windows/security/identity-protection/credential-guard/)

## Historial de versiones

| Versión | Cambios |
|---|---|
| 1.0.0 | Versión inicial: petición y validación del destino (FQDN, IP o UNC), 9 comprobaciones, diagnóstico y siguientes pasos calculados, bilingüe (es/en), código de salida para RMM. |

## Licencia

MIT, como el resto del repositorio.
