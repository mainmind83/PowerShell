# Claude + CAD

**Install-ClaudeCad.ps1 · v1.4.1 · by [mainmind.com](https://mainmind.com)**

[🇪🇸 Español](README.md) · 🇬🇧 English

Windows installer that connects **Claude Desktop** to **FreeCAD** through MCP (Model Context Protocol), using the open-source project [neka-nat/freecad-mcp](https://github.com/neka-nat/freecad-mcp). Once it finishes, Claude can create and edit models, inspect documents and run Python code inside FreeCAD.

## How the bridge works

```
Claude Desktop ──stdio──> MCP server (uvx freecad-mcp) ──XML-RPC localhost:9875──> FreeCADMCP addon (inside FreeCAD)
```

There are two parts: an **addon** that runs inside FreeCAD and opens a local RPC server, and an **MCP server** launched by Claude Desktop that turns Claude's requests into RPC calls.

## Requirements

- Windows 10/11 with PowerShell 5.1 or later
- FreeCAD 1.0 or later, **opened at least once after installing** (that is when it creates its user folder)
- Claude Desktop
- Optional: git (without git, the repository is downloaded as a ZIP)

## Download

Clone the repository or download just this folder, and copy `Install-ClaudeCad.ps1` into your working directory (default `C:\mainmind\ClaudeCad`):

```powershell
New-Item -ItemType Directory -Path C:\mainmind\ClaudeCad -Force | Out-Null
Invoke-WebRequest https://raw.githubusercontent.com/mainmind83/PowerShell/main/ClaudeCad/Install-ClaudeCad.ps1 -OutFile C:\mainmind\ClaudeCad\Install-ClaudeCad.ps1
Unblock-File C:\mainmind\ClaudeCad\Install-ClaudeCad.ps1
```

Read any script you download from the internet before running it. This one changes the Claude Desktop and FreeCAD configuration.

## Usage

```powershell
cd C:\mainmind\ClaudeCad
powershell -ExecutionPolicy Bypass -File .\Install-ClaudeCad.ps1 -Lang en
```

| Parameter | Description |
|---|---|
| `-Lang es\|en` | Message language. If omitted, the Windows language is detected and you are asked (Enter accepts the detected one). |
| `-WorkDir <path>` | Working directory. Default `C:\mainmind\ClaudeCad`. |
| `-FreeCADUserDir <path>` | Forces the FreeCAD user folder if detection fails (output of `FreeCAD.getUserAppDataDir()` in FreeCAD's Python console). |
| `-SkipClaudeConfig` | Leaves Claude Desktop's configuration untouched. |
| `-Feedback text\|image` | FreeCAD feedback mode towards Claude. `text` adds `--only-text-feedback` (fewer tokens). If omitted, it is explained and asked on every run (Enter keeps the current mode). |
| `-Force` | Redoes every step even if it is already done. |

## What it does, step by step

1. **Working directory.** Creates `C:\mainmind\ClaudeCad` if it does not exist.
2. **Repository.** Clones `neka-nat/freecad-mcp` into `WorkDir\freecad-mcp`. If it is already cloned, runs `git pull` and reports whether anything changed. Without git, downloads it as a ZIP.
3. **uv.** Uses `uv`/`uvx` from `WorkDir\bin`, or installs it there if missing. It does not change your PATH or user profile.
4. **FreeCAD user folder.** Looks in the default path `%APPDATA%\FreeCAD\vX-Y` and picks the highest version if there are several. If none is found, asks you to open FreeCAD once and asks (Y/N) before continuing. Creates the `Mod` folder if it is missing, which is normal until the first addon is installed.
5. **Addon.** Copies `addon\FreeCADMCP` to `Mod\FreeCADMCP`. Compares SHA-256 fingerprints and only copies when something differs.
6. **Claude Desktop configuration.** Adds the `freecad` entry to `claude_desktop_config.json`, with the absolute path to `uvx.exe`. Keeps all other entries, makes a backup (`.bak-date`) only when it is going to write, and saves as UTF-8 without BOM. Also detects the Microsoft Store (MSIX) install.
   - **Feedback mode.** On every run it shows the current mode and asks whether to use **text-only** mode (`--only-text-feedback`):
     - *Images + text* (default): every operation also returns a screenshot of the model. Claude sees the result, but each screenshot costs considerably more tokens.
     - *Text only*: returns object names, dimensions and success/error. Uses **far fewer tokens**. Claude can still ask for a view when needed with `get_view`.
   - Keeps any arguments and environment variables the entry already had (for example `--host` or `FREECAD_MCP_TOKEN`).

7–9. **RPC server auto-start, security and status.** Reads the addon settings (`freecad_mcp_settings.json` in the FreeCAD user folder) and:
   - If auto-start is off, asks *Do you want the MCP server to always auto-start with FreeCAD?* and, if you answer Y, turns on `auto_start_rpc`. The change applies the next time you open FreeCAD.
   - Checks the allowed IP list and **warns** if it contains anything other than localhost (`127.0.0.1`, `::1`, `localhost`). It also warns if remote connections are enabled, or enabled without an auth token. It only warns: it does not change those values.
   - Checks whether FreeCAD is running and, if not, offers to open it.
   - Checks whether the RPC server is listening on port 9875 and on which address. Warns if it is exposed to the network (not loopback).

10. **Claude Desktop.** Checks whether Claude Desktop is running. It tells the desktop app apart from Claude Code, which is also called `claude.exe`.

At the end it prints a **summary** and **next steps based on the actual state**. It only asks you to restart FreeCAD if it was open when the addon was installed or updated, or if auto-start was enabled while FreeCAD was already open without RPC. If FreeCAD was closed, it just tells you to open it. It only asks you to restart Claude Desktop if `claude_desktop_config.json` changed and the app is open. If nothing is needed, it says everything is ready.

## Idempotency

You can run it as many times as you like. Each step checks its own state and, if it is already done, skips it and says so with `[SKIP]`. If nothing changes, the script says so and touches no files. It also works as an updater: if the repository has changes, the addon and anything else needed are updated.

## After installing

Follow the *next steps* the script prints at the end: they depend on whether FreeCAD and Claude Desktop were open and on what changed.

## Screenshots

**FreeCAD (1.1.4):** *MCP Addon* workbench and its toolbar. *Auto-Start Server* shows as pressed when auto-start is enabled.

![MCP addon toolbar in FreeCAD](docs/img/freecad-mcp-toolbar.png)

**Claude Desktop:** the `freecad` connector shows up under *Connectors* and can be turned on or off per conversation.

![freecad connector in Claude Desktop](docs/img/claude-desktop-freecad-connector.png)

## Security

- The `execute_code` tool runs **arbitrary Python** inside FreeCAD with your user permissions.
- **Do not enable the addon's remote connections without first reviewing security and network access.** By default the RPC server must listen on `localhost` only.
- Avoid combining this MCP with reading external content (web pages, emails) in the same conversation. A prompt injection could end up running code on your machine.

## Known limitations

- The addon comes from GitHub's `main` branch, while `uvx freecad-mcp` uses the latest release on PyPI. If they are ever incompatible, point Claude at the local repository with `uvx --from C:\mainmind\ClaudeCad\freecad-mcp freecad-mcp`.
- The interactive prompts (language, step 4 Y/N and the steps 7–9 questions) block unattended runs. Use `-Lang` and `-FreeCADUserDir` in that case; the steps 7–9 questions remain interactive.

## Version history

| Version | Changes |
|---|---|
| 1.4.1 | The feedback mode question is asked on every run, showing the current mode (Enter keeps it). |
| 1.4.0 | Text-only mode option (`--only-text-feedback`) in Claude's configuration, with prompt and `-Feedback` parameter. Keeps existing args and `env`. |
| 1.3.0 | Step 10: Claude Desktop detection. Next steps based on the actual state (no unnecessary restarts). Revised security note. |
| 1.2.0 | Steps 7–9: FreeCAD and RPC server status, auto-start prompt, security warnings for allowed IPs, remote connections and token. |
| 1.1.0 | Bilingual (es/en) with language detection and selector; banner; full idempotency with final summary; `-Force` parameter. |
| 1.0.0 | Initial version: uv in `WorkDir\bin`, `%APPDATA%\FreeCAD\vX-Y` detection, Y/N prompt, `Mod` creation, Claude Desktop configuration. |

## License

MIT, like the rest of the repository. The code of [neka-nat/freecad-mcp](https://github.com/neka-nat/freecad-mcp) (also MIT) is not included here: the script downloads it from its original repository.
