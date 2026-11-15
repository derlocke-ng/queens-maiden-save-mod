# QDQuickSave – Quicksave & Quickload for Queen's Domain

[![CI](https://github.com/derlocke-ng/queens-maiden-save-mod/actions/workflows/ci.yml/badge.svg)](https://github.com/derlocke-ng/queens-maiden-save-mod/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/derlocke-ng/queens-maiden-save-mod)](https://github.com/derlocke-ng/queens-maiden-save-mod/releases/latest)

Press **F5** to quicksave anywhere and **F9 twice** to go back to it, even from the death screen.
Both keys can be changed.

- **Your normal saves are never touched.** A quicksave is a separate file next to them.
- **One quicksave per save slot**, restoring position, health, inventory and progress.
- **Uses the game's own save code.** The game quietly writes a "suspend save" every two minutes and resumes it
  when you load the slot (crash protection it never mentions). A quicksave is a copy of that save, and loading one
  is the game's own resume.
- Windows, Linux and Steam Deck.

> Unofficial fan mod. Not made or supported by Freshly Baked Games.

**Contents:** [Install](#install) · [How to use](#how-to-use) · [Change the hotkeys](#change-the-hotkeys) ·
[What a quicksave restores](#what-a-quicksave-restores) · [Update](#update) · [Uninstall](#uninstall) ·
[Troubleshooting](#troubleshooting) · [Safety](#safety) · [For developers](#for-developers)

---

## Install

### Windows

1. Download **[QDQuickSave-with-UE4SS.zip](https://github.com/derlocke-ng/queens-maiden-save-mod/releases/latest/download/QDQuickSave-with-UE4SS.zip)**
   (always the newest version; older ones are on the [Releases](https://github.com/derlocke-ng/queens-maiden-save-mod/releases) page).
2. Open the game folder: in Steam, right-click *Queen's Domain* → **Manage** → **Browse local files**.
   It is the folder that contains `QueensDomain.exe`.
3. Extract the zip **into that folder**, keeping the folder structure.
4. Check that `QueensDomain\Binaries\Win64\dwmapi.dll` now exists, then start the game.

### Linux, Steam Deck, Proton, Bottles, Lutris

Do the Windows steps, then tell Wine to load the mod loader (once):

- **Steam / Steam Deck (Proton):** right-click the game → **Properties** → **Launch options**, paste:
  ```
  WINEDLLOVERRIDES="dwmapi=n,b" %command%
  ```
- **Bottles:** open the bottle → **Settings** → **DLL overrides** → add `dwmapi`, set to **Native, then Builtin**.
- **Lutris:** right-click the game → **Configure** → **Runner options** → **DLL overrides** → add `dwmapi` = `n,b`.

Without this step the mod does not load, because Wine uses its own `dwmapi.dll` instead of the mod loader's.

### Already using UE4SS?

Download **[QDQuickSave.zip](https://github.com/derlocke-ng/queens-maiden-save-mod/releases/latest/download/QDQuickSave.zip)**
(the mod only) and extract it into the game folder. It adds
`QueensDomain/Binaries/Win64/ue4ss/Mods/QDQuickSave/`, enabled by its `enabled.txt`.

## How to use

| Default key | Where | What happens |
|---|---|---|
| **F5** | while playing | Quicksave. *"Quicksave saved - Slot N"* appears at the top of the screen. |
| **F9**, then **F9** again within 3 s | while playing, or on the death screen | Loads your quicksave. *"Quicksave loaded - Slot N"* appears when you are back. |
| **F9** | title screen: **Play** → highlight a slot | Prepares that slot's quicksave; select the slot to load it. |

Good to know:

- **Save at a Crystal Monument once** in a new game. Until then the game treats the slot as empty and quicksaving
  is refused.
- The keys do nothing in menus, shops, dialogues and cutscenes, while resting at a Crystal Monument, or where the
  game itself blocks saving. Quicksaving is also refused while dying and on the death screen. The message says why.
- Each save slot has **one** quicksave. A new one replaces it; the previous one is kept as a `.prev` backup file.
- The death screen's own **Continue** still goes back to your last Crystal Monument save. Press the quickload key
  twice instead to continue from your quicksave.
- A quicksave still loads after you have saved at a Crystal Monument later on. It takes you back to the quicksave;
  the Crystal Monument save stays as it is.

## Change the hotkeys

Open this file in a text editor (Notepad is fine):

```
QueensDomain\Binaries\Win64\ue4ss\Mods\QDQuickSave\config.ini
```

Change the key after the `=`, save the file and restart the game:

```ini
QuickSave = F5
QuickLoad = F9
```

| You can use | Written as |
|---|---|
| Function keys | `F1` … `F12` |
| Letters and digits | `A` … `Z`, `0` … `9` |
| Numpad | `Num0` … `Num9` |
| Navigation | `Insert`, `Delete`, `Home`, `End`, `PageUp`, `PageDown`, `Up`, `Down`, `Left`, `Right` |
| Other | `Tab`, `Space`, `Backspace`, `Enter`, `Pause` |
| With a modifier | `Ctrl+S`, `Shift+F9`, `Ctrl+Alt+Q` (modifiers: `Ctrl`, `Shift`, `Alt`) |

Any other name from UE4SS's [key list](https://docs.ue4ss.com/lua-api/table-definitions/key.html) works too.
Upper and lower case do not matter.

- Use **two different keys**, and keys the game does not already use: the game still reacts to its own bindings.
- A name the mod does not know falls back to F5 / F9. The game shows a message on the title screen and
  `ue4ss/UE4SS.log` has the reason.
- The messages on screen name the keys you chose.
- Without a `config.ini` the mod uses F5 and F9.

## What a quicksave restores

Tested in game:

- your **position** (a quicksave made mid-jump puts you on the ground below),
- your **health**,
- your **inventory and consumables** (a herb used after quicksaving is back),
- items picked up after quicksaving are back in the world,
- story and progress flags, notes and the loaded area, the same way the game's own suspend save does.

The rest of the world (enemies and so on) is set up the way the game always does when it loads a save.

## Update

Extract the new zip into the game folder and let it replace the old files. Your quicksaves stay.

Updating replaces `config.ini`. If you changed your hotkeys, copy the file somewhere first and put it back after.

## Uninstall

Delete these from `QueensDomain/Binaries/Win64/`:

- `dwmapi.dll`
- the `ue4ss` folder

With the mod-only zip and your own UE4SS, delete just `ue4ss/Mods/QDQuickSave`.
On Linux, also remove the launch option or DLL override.

Quicksave files stay in your save folder until you delete them, and are harmless if left there:
`%LOCALAPPDATA%\QueensDomain\Saved\SaveGames\<number>\QuickSave_World*.sav` (and `.sav.prev`).

## Troubleshooting

- **Nothing happens at all.** Check that `QueensDomain/Binaries/Win64/ue4ss/UE4SS.log` exists after starting the
  game. No log means the mod loader is not running: `dwmapi.dll` must sit next to
  `QueensDomain-Win64-Shipping.exe` (not in a second `Win64` folder inside `Win64`), and Linux needs the DLL
  override.
- **"Save at a Crystal Monument in this slot first".** Rest and save at a Crystal Monument once in that slot.
- **My new hotkey does nothing.** Look for `[QDQuickSave] config.ini:` in `ue4ss/UE4SS.log`; it names the line the
  mod could not read. Restart the game after every change to `config.ini`.
- **No message on screen.** Every message is also written to `ue4ss/UE4SS.log`, in lines starting with
  `[QDQuickSave]`.
- **It stopped working after a game update.** Install the newest release. If that does not help, please
  [open an issue](https://github.com/derlocke-ng/queens-maiden-save-mod/issues) and attach `ue4ss/UE4SS.log`.

## Safety

- The mod never writes your normal saves (`World<N>.sav`, `World<N>_backup.sav`), your settings (`System0.sav`) or
  your challenge progress.
- It only writes `QuickSave_World<N>.sav` (and `.prev`) and, when you load a quicksave, the game's own temporary
  suspend files `World<N>_Suspend_0/1.sav`, which the game rewrites every two minutes and deletes when you quit.
- Still a good habit before trying any mod: copy your save folder somewhere safe
  (`%LOCALAPPDATA%\QueensDomain\Saved`).

## Tested with

- Queen's Domain **1.01.07** (Unreal Engine 4.27.2)
- UE4SS **v4.0.0**, the build included in the `-with-UE4SS` zip
- Linux (Fedora Silverblue) with Steam and Bottles, and Windows 11
- Other mods and other UE4SS versions may work.

## For developers

```
python3 tools/build_release.py           # builds dist/*.zip for the version in VERSION
```

**Releasing:** change the version in `VERSION` (e.g. `1.0.0` → `1.0.1`) and push to `main`. The *Release* workflow
then builds both zips, creates the tag `v1.0.1` and publishes the GitHub Release. Nothing happens if the tag exists.

- Mod source: `mods/QDQuickSave/Scripts/main.lua`; default hotkeys: `mods/QDQuickSave/config.ini`.
- `mods/QuickSaveProbe` is a logging-only research tool and is not shipped.
- The bundled UE4SS build is pinned in `packaging/ue4ss.lock.json` (URL and SHA-256).
- Steam guide text: `media/steam-guide.txt`; its images come from `tools/make_steam_images.py`.

## Credits & licence

- QDQuickSave is released under the [MIT licence](LICENSE).
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS), the mod loader (MIT licence, included in the bundle as
  `ue4ss/LICENSE`).
- Queen's Domain by Freshly Baked Games. This project contains no game files.
- Thanks to @bahcall (Steam) for the fix for game versions after 1.01.06.
- [Steam guide](https://steamcommunity.com/sharedfiles/filedetails/?id=3831364891)
