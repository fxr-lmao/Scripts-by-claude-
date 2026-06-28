# Roblox Scripts

Roblox Luau scripts. Unless noted otherwise, each is a **LocalScript** meant for
`StarterPlayer > StarterPlayerScripts`.

## Index

| Script | Type | Description |
|--------|------|-------------|
| [`CinematicHub.lua`](CinematicHub.lua) | Loader | All-in-one cinematic tools hub — one floating button opens a tabbed, exploit-hub-style panel for **Free Cam**, **Shaders**, **Fonts**, **World**, and **Extras**. Thin loader that pulls the modules in [`cinematic/`](cinematic). Everything is client-side and visual only — no exploits. |
| [`cinematic/`](cinematic) | Modules | The hub's source, split into `Lib`, `Shell`, `FreeCam`, `Shaders`, `Fonts`, `World`, `Extras`. |

## CinematicHub.lua

Run it with an executor:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/fxr-lmao/Scripts-by-claude-/refs/heads/claude/hub-freecam-qol-0jgtb0/roblox/CinematicHub.lua"))()
```

`CinematicHub.lua` is a thin **loader**; it fetches the modules in `cinematic/`
from the same branch. The loader's `SOURCE.ref` must point at a branch/commit
that contains `cinematic/` — switch it to `refs/heads/main` after merging. (In
Studio, parent the `cinematic/` ModuleScripts under the loader and it `require`s
them locally instead of over HTTP.) It's also auto-execute safe — it waits for
the game and local player to load, so it can live in an executor's autoexec
folder.

| Action | Input |
|--------|-------|
| Open / close hub | Drag-anywhere **🎬 Cinematic** button, or press **`\`** (backquote) |
| Toggle Free Cam directly | `P` |

Every tab page **scrolls by dragging anywhere on it** (no scroll wheel needed)
as well as via the scrollbar.

- **Free Cam** — detaches the camera and hides all UI for a clean shot; the
  launcher is hidden while flying, with an always-there on-screen Exit button.
- **Shaders** — preset buttons (Default, Cinematic, Noir, Warm, Cold, Dreamy,
  Horror, Vintage, Vaporwave) plus manual Bloom / Blur / Brightness / Contrast /
  Saturation / Sun Rays sliders. Bloom uses a low threshold so the glow is
  actually visible.
- **Fonts** — click a font (35+ options) to re-skin the hub, every other UI
  under `PlayerGui`, and chat (window + bubbles via `TextChatService`). Inert
  until you pick one, then a single `DescendantAdded` listener catches new UI —
  no polling loops, so no frame-rate overhead. The font-list buttons keep their
  own font so each stays a live preview.
- **World** — time-of-day slider + Dawn/Noon/Sunset/Night buttons, camera FOV,
  atmosphere haze, a freeze-time toggle that genuinely holds the clock, and a
  timelapse toggle (with speed) that sweeps the sun.
- **Extras** — letterbox bars (+ size), hide nameplates/healthbars, hide game
  UI, and Reset All.

### Free Cam — controls

**Desktop**

| Action | Input |
|--------|-------|
| Toggle | `P` or the tab's **Enter / Exit Free Cam** button |
| Move | `W` `A` `S` `D` / arrows |
| Up / Down | `E` / `Q` |
| Look | Mouse (cursor locks to centre while active) |
| Boost / Slow | `Shift` / `Ctrl` |
| Speed | **Move Speed** slider in the tab |

**Mobile**

| Action | Input |
|--------|-------|
| Toggle | Free Cam tab button, or the on-screen **Exit** button |
| Move | Drag anywhere on the **left half** — a joystick spawns under your thumb and trails it |
| Up / Down | ▲ / ▼ buttons |
| Look | Drag the **right half** of the screen |
| Speed | **Move Speed** slider in the tab |

Purely client-side — it only moves your camera, never your character, and uses
the supported `SetCoreGuiEnabled` / `SetCore` / `GuiService` APIs to hide UI.
While the free cam is active, character controls are disabled via the
`PlayerModule` (and the root part anchored), so moving the joystick or pressing
WASD flies the camera **without walking your avatar around**. Both are restored
on exit.
