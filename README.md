# PowerShell
Scripts y automatizaciones para frikis de IT

## Contenido

| Carpeta / script | Descripción |
|---|---|
| [ClaudeCad](ClaudeCad/) | Instalador idempotente y bilingüe que conecta Claude Desktop con FreeCAD mediante MCP (`Install-ClaudeCad.ps1`). |
| [AdminLocalReport](AdminLocalReport) | Audita los miembros del grupo de Administradores locales de Windows, con independencia del idioma y de si el equipo está en dominio. Devuelve `OK` o `ALERTA` con los usuarios inesperados; pensado como campo personalizado en un RMM. |
| [Azure/Delete_backups](Azure/Delete_backups) | Elimina un Recovery Services Vault de Azure y todos sus elementos asociados (backups de VM, SQL, SAP HANA, Azure Files, MARS/MABS/DPM, ASR). |
| [DLNA-legacy-converter.ps1](DLNA-legacy-converter.ps1) | Prepara vídeos `.avi`/`.mkv`/`.mp4` para reproducción directa en televisores DLNA antiguos (2012-2018). Analiza cada fichero con ffprobe y solo remultiplexa o recodifica lo necesario. |
| [Desbloquear-all.ps1](Desbloquear-all.ps1) | Desbloquea cualquier tipo de archivo (quita la marca `Zone.Identifier`) en un fichero o una carpeta, con opción recursiva. |
| [Desbloquear-docs.ps1](Desbloquear-docs.ps1) | Desbloquea ficheros PDF, Word, Excel y PowerPoint de una carpeta. |
| [JtR-status.ps1](JtR-status.ps1) | Muestra el estado de las sesiones activas de John the Ripper en Windows, con refresco automático y autodetección de `john.exe`. |
| [MultiWanLegacy.ps1](MultiWanLegacy.ps1) | Comprueba la IP pública de salida al acceder a distintos grupos de URLs (administraciones públicas, eIDAS, factura electrónica, justicia…) para diagnosticar escenarios con varias conexiones a Internet. |
