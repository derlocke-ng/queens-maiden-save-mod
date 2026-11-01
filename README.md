# QDQuickSave – Quicksave & Quickload for Queens Domain

[![CI](https://github.com/derlocke-ng/queens-maiden-save-mod/actions/workflows/ci.yml/badge.svg)](https://github.com/derlocke-ng/queens-maiden-save-mod/actions/workflows/ci.yml)

Press **F5** to quicksave anywhere, press **F9 twice** to jump back to it, even from the death screen.

This mod uses the game's own built-in "suspend save" (the save the game quietly writes every two minutes for crash
protection), so loading a quicksave is the same thing the game does when it recovers from a crash. **Your normal
saves are never touched.**

> Unofficial fan mod. Not made or supported by Freshly Baked Games.

---

## Quick start (Windows)

New to mods? Follow the short [Windows tutorial](docs/INSTALL-WINDOWS.md).

1. Download **[QDQuickSave-with-UE4SS.zip](https://github.com/derlocke-ng/queens-maiden-save-mod/releases/latest/download/QDQuickSave-with-UE4SS.zip)**
   (always the newest version; all versions are on the [Releases](https://github.com/derlocke-ng/queens-maiden-save-mod/releases) page).
2. Open the game folder: in Steam, right-click *Queens Domain* → **Manage** → **Browse local files**.
   It is the folder that contains `QueensDomain.exe`.
3. Extract the zip **into that folder** (keep the folder structure). Done – start the game.

## Quick start (Linux, Steam Deck, Proton, Bottles, Lutris)

Do steps 1–3 above, then tell Wine to load the mod loader (one-time step):

- **Steam / Steam Deck (Proton):** right-click the game → **Properties** → **Launch options**, paste:
  ```
  WINEDLLOVERRIDES="dwmapi=n,b" %command%
  ```
- **Bottles:** open the bottle → **Settings** → **DLL overrides** → add `dwmapi` and set it to **Native, then Builtin**.
- **Lutris:** right-click the game → **Configure** → **Runner options** → **DLL overrides** → add `dwmapi` = `n,b`.

Without this step nothing happens when you press F5 (Wine uses its own `dwmapi.dll` instead of the mod loader's).

## How to use

| Key | Where | What happens |
|---|---|---|
| **F5** | while playing | Quicksave. A message *"Quicksave saved - Slot N"* appears at the top of the screen. |
| **F9**, then **F9** again within 3 s | while playing, or on the death screen | Loads your quicksave. *"Quicksave loaded - Slot N"* appears when you're back. |
| **F9** | title screen: **Play** → highlight a slot | Prepares that slot's quicksave; then select the slot to load it. |

Good to know:

- **Save at a monolith once** in a new game first. Before that, the game treats the slot as empty and F5 refuses.
- F5 and F9 do nothing in menus, shops, dialogues, cutscenes, while resting at a monolith, or in places where the game
  itself blocks saving (F5 also not on the death screen); the message tells you why.
- Each save slot has **one** quicksave. A new F5 replaces it (the previous one is kept as a backup file, see below).
- The death screen's own **Continue** still goes back to your last monolith save – press **F9 twice** instead to
  continue from your quicksave.
- Loading a quicksave also works if you saved at a monolith after quicksaving. It takes you back to the quicksave
  (your monolith save itself stays untouched).

## What a quicksave restores

Tested in game:

- your **position** (if you quicksave mid-jump you land on the ground below),
- your **health**,
- your **inventory and consumables** (e.g. a herb used after quicksaving is back),
- items you picked up after quicksaving are back in the world,
- story/progress flags, notes and the loaded area, the same way the game's own suspend save does.

The rest of the world (enemies, etc.) is set up the way the game always does when it loads a save.

## Uninstall

Delete these from the game's `QueensDomain/Binaries/Win64/` folder:

- `dwmapi.dll`
- the `ue4ss` folder

(If you used the mod-only zip with your own UE4SS: delete just `ue4ss/Mods/QDQuickSave`.)

On Linux, also remove the launch option / DLL override again.

Quicksave files stay in your save folder until you delete them (harmless if left there):
`%LOCALAPPDATA%\QueensDomain\Saved\SaveGames\<number>\QuickSave_World*.sav` (and `.sav.prev`).

## Already using UE4SS?

Download **`QDQuickSave-<version>.zip`** (mod only) and extract it into the game folder. It adds
`QueensDomain/Binaries/Win64/ue4ss/Mods/QDQuickSave/` (enabled via its `enabled.txt`).

## Troubleshooting

- **Nothing happens at all.** Check that `QueensDomain/Binaries/Win64/ue4ss/UE4SS.log` exists after starting the game.
  No log → the mod loader is not running: re-check the folder you extracted to (`dwmapi.dll` must sit next to
  `QueensDomain-Win64-Shipping.exe`) and, on Linux, the DLL override.
- **"Save at a monolith in this slot first"** – exactly that: rest/save at a monolith once, then F5 works.
- **No message on screen** – every message is also written to `ue4ss/UE4SS.log` (lines starting with `[QDQuickSave]`).
- **After a game update** the mod loader may need an update too. Remove the mod (see Uninstall) and check for a new
  release here.

## Safety

- The mod never writes your normal saves (`World<N>.sav`, `World<N>_backup.sav`), your settings (`System0.sav`) or
  challenge progress.
- It only writes `QuickSave_World<N>.sav` (+ `.prev`) and, when you load a quicksave, the game's own temporary
  suspend files `World<N>_Suspend_0/1.sav` (which the game itself rewrites every two minutes and deletes when you quit).
- Still a good habit before trying any mod: copy your save folder somewhere safe
  (`%LOCALAPPDATA%\QueensDomain\Saved`).

## Tested with

- Queens Domain **1.01.00** (build 13464, Unreal Engine 4.27.2)
- UE4SS experimental build **e84db30c** (the one included in the `-with-UE4SS` zip)
- Linux (Fedora Silverblue) with Bottles. Windows itself has not been tested yet – reports welcome.

## For developers

```
python3 tools/build_release.py --version 1.2.3            # builds dist/*.zip
git tag v1.2.3 && git push origin v1.2.3                 # CI publishes a GitHub Release
```

- Mod source: `mods/QDQuickSave/Scripts/main.lua`. `mods/QuickSaveProbe` is a logging-only research tool (not shipped).
- The bundled UE4SS build is pinned in `packaging/ue4ss.lock.json` (URL + SHA-256).

## Credits & licence

- QDQuickSave is released under the [MIT licence](LICENSE).
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) – the mod loader (MIT licence, included in the bundle as `ue4ss/LICENSE`).
- Queens Domain by Freshly Baked Games. This project contains no game files.
