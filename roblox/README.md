# Roblox Scripts

Roblox Luau scripts. Unless noted otherwise, each is a **LocalScript** meant for
`StarterPlayer > StarterPlayerScripts`.

## Index

| Script | Type | Description |
|--------|------|-------------|
| [`FreeCam.lua`](FreeCam.lua) | LocalScript | Cross-platform cinematic free camera. Detaches from your character and hides **all** UI (player + core/topbar/chat/backpack/health/leaderboard) for clean shots. Desktop (WASD + mouse) and full mobile (thumbstick, ▲/▼, drag-to-look, speed slider). Toggle with **P** or the on-screen button. |
| [`CinematicHub.lua`](CinematicHub.lua) | Loader | All-in-one cinematic tools hub — one floating button opens a tabbed, exploit-hub-style panel for **Free Cam**, **Shaders**, **Fonts**, **World**, and **Extras**. Thin loader that pulls the modules in [`cinematic/`](cinematic). Everything is client-side and visual only — no exploits. |
| [`cinematic/`](cinematic) | Modules | The hub's source, split into `Lib`, `Shell`, `FreeCam`, `Shaders`, `Fonts`, `World`, `Extras`. |

## FreeCam.lua — controls

**Desktop**

| Action | Input |
|--------|-------|
| Toggle | `P` or on-screen button |
| Move | `W` `A` `S` `D` / arrows |
| Up / Down | `E` / `Q` |
| Look | Mouse |
| Boost / Slow | `Shift` / `Ctrl` |
| Speed | Slider (top of screen) |

**Mobile**

| Action | Input |
|--------|-------|
| Toggle | On-screen **Free Cam** button |
| Move | Left thumbstick |
| Up / Down | ▲ / ▼ buttons |
| Look | Drag the right half of the screen |
| Speed | Slider (top of screen) |

Purely client-side — it only moves your camera, never your character, and uses
the supported `SetCoreGuiEnabled` / `SetCore` / `GuiService` APIs to hide UI.

## CinematicHub.lua

Run it with an executor:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/fxr-lmao/Scripts-by-claude-/refs/heads/claude/cinematic-tools-ui-jri78q/roblox/CinematicHub.lua"))()
```

`CinematicHub.lua` is a thin **loader**; it fetches the modules in `cinematic/`
from the same branch. The loader's `SOURCE.ref` must point at a branch/commit
that contains `cinematic/` — switch it to `refs/heads/main` after merging. (In
Studio, parent the `cinematic/` ModuleScripts under the loader and it `require`s
them locally instead of over HTTP.)

| Action | Input |
|--------|-------|
| Open / close hub | Drag-anywhere **🎬 Cinematic** button, or press **`\`** (backquote) |
| Toggle Free Cam directly | `P` |

Every tab page **scrolls by dragging anywhere on it** (no scroll wheel needed)
as well as via the scrollbar.

- **Free Cam** — same controls as `FreeCam.lua`; hides the launcher for a clean
  shot, with an on-screen Exit button on mobile.
- **Shaders** — preset buttons (Default, Cinematic, Noir, Warm, Cold, Dreamy,
  Horror, Vintage, Vaporwave) plus manual Bloom / Blur / Brightness / Contrast /
  Saturation / Sun Rays sliders. Bloom uses a low threshold so the glow is
  actually visible.
- **Fonts** — click a font (35+ options) to re-skin the hub, every other UI
  under `PlayerGui`, and chat (window + bubbles via `TextChatService`). Inert
  until you pick one, then a single `DescendantAdded` listener catches new UI —
  no polling loops, so no frame-rate overhead.
- **World** — time-of-day slider + Dawn/Noon/Sunset/Night buttons, camera FOV,
  atmosphere haze, a freeze-time toggle that genuinely holds the clock, and a
  timelapse toggle (with speed) that sweeps the sun.
- **Extras** — letterbox bars (+ size), hide nameplates/healthbars, hide game
  UI, and Reset All.

Run either `FreeCam.lua` **or** `CinematicHub.lua` — the hub already includes
free cam, so you don't need both.
