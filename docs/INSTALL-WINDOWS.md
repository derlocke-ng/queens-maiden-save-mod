# QDQuickSave – Quicksave & Quickload for Queens Domain (Windows)

Press **F5** to quicksave anywhere, press **F9 twice** to load it – even from the death screen.
Your normal saves are never touched.

## Install (2 minutes)

1. **Download:** [QDQuickSave-with-UE4SS.zip](https://github.com/derlocke-ng/queens-maiden-save-mod/releases/latest/download/QDQuickSave-with-UE4SS.zip)
2. **Open the game folder:** in Steam, right-click *Queens Domain* → **Manage** → **Browse local files**.
   It is the folder with `QueensDomain.exe` in it.
3. **Extract:** right-click the downloaded zip → **Extract All…** → choose the game folder from step 2 → **Extract**.
   *Check:* the file `QueensDomain\Binaries\Win64\dwmapi.dll` now exists.
4. **Start the game.** That's it.

## How to use

- **F5** – quicksave. *"Quicksave saved"* appears at the top of the screen.
- **F9, then F9 again** – load your quicksave (also on the death screen).
- In a new game, **save at a monolith once** first – before that, F5 doesn't work.
- F5 doesn't work in menus, dialogues, cutscenes or while resting at a monolith; the message tells you why.

## Uninstall

Delete `dwmapi.dll` and the `ue4ss` folder from `QueensDomain\Binaries\Win64`.

## More info

Linux / Steam Deck setup, what a quicksave restores, troubleshooting:
see the [README](https://github.com/derlocke-ng/queens-maiden-save-mod#readme).

*Tested on Linux so far – Windows feedback is welcome.*
