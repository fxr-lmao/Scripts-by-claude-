# Roblox Scripts

Roblox Luau scripts. Unless noted otherwise, each is a **LocalScript** meant for
`StarterPlayer > StarterPlayerScripts`.

## Index

| Script | Type | Description |
|--------|------|-------------|
| [`dist/Mirage.lua`](dist/Mirage.lua) | Bundle | **Published, one-file build** of the hub (**Mirage**) — all modules inlined behind a junk-padded XOR+base64 decoder. This is what you `loadstring`. Regenerate with `build/bundle.py`. |
| [`CinematicHub.lua`](CinematicHub.lua) | Loader (dev) | Thin loader that pulls the modules in [`cinematic/`](cinematic) over HTTP — handy for development. One floating button opens a tabbed panel: **Free Cam**, **Shaders**, **Fonts**, **World**, **Client**, **Fun**, **Extras**. Everything is client-side only — it never touches the server or other players. |
| [`cinematic/`](cinematic) | Modules | The hub's source, split into `Lib`, `Shell`, `FreeCam`, `Shaders`, `Fonts`, `World`, `Client`, `Fun`, `Extras`. |
| [`build/bundle.py`](build/bundle.py) | Build | Inlines `cinematic/` into [`dist/Mirage.lua`](dist/Mirage.lua). Run after editing any module. |

## Mirage (CinematicHub)

The hub is branded **Mirage** (the launcher button reads `✨ Mirage`). The brand
is a single constant — `Lib.BRAND` / `Lib.GLYPH` in [`cinematic/Lib.lua`](cinematic/Lib.lua) —
so renaming it again is a one-line edit (then rebuild the bundle, below).

**To publish / run** — use the bundled, single-file build:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/fxr-lmao/Scripts-by-claude-/refs/heads/claude/hub-freecam-qol-0jgtb0/roblox/dist/Mirage.lua"))()
```

[`dist/Mirage.lua`](dist/Mirage.lua) inlines every module into one self-contained
chunk (no per-module HTTP) behind a junk-padded XOR+base64 decoder, so it isn't
casually copy-pasteable and the GUI name is randomised per run. **This is light
anti-skid, not real obfuscation** — the readable source still lives in
`cinematic/`, and a determined reader can recover it. For stronger protection,
run the dist file through a dedicated Lua obfuscator before publishing.

**To rebuild the bundle** after editing anything in `cinematic/`:

```sh
python3 roblox/build/bundle.py    # regenerates roblox/dist/Mirage.lua
```

**For development**, [`CinematicHub.lua`](CinematicHub.lua) is a thin **loader**
that fetches the `cinematic/` modules over HTTP from a branch (set its
`SOURCE.ref`; switch to `refs/heads/main` after merging). In Studio, parent the
`cinematic/` ModuleScripts under the loader and it `require`s them locally.

Both entry points are auto-execute safe — they wait for the game and local
player to load, so either can live in an executor's autoexec folder.

| Action | Input |
|--------|-------|
| Open / close hub | Drag-anywhere **✨ Mirage** button, or press **`\`** (backquote) |
| Toggle Free Cam directly | `P` |

Every tab page **scrolls by dragging anywhere on it** (no scroll wheel needed)
as well as via the scrollbar.

- **Free Cam** — detaches the camera and hides all UI for a clean shot; the
  launcher is hidden while flying, with an always-there on-screen Exit button.
  Includes a **rule-of-thirds framing grid** toggle, and a **clean-shot timer**
  (3 / 5 / 10 / 30 s buttons while flying) that hides every overlay for that long
  then restores it — for grabbing footage with nothing on screen.
- **Shaders** — preset buttons (Default, **Realistic**, **Ultra**, Cinematic,
  Noir, Warm, Cold, Dreamy, Horror, Vintage, Vaporwave, Cyberpunk) plus manual
  Bloom / Blur / Brightness / Contrast / Saturation / Sun Rays sliders. A
  **Realism** block drives the Roblox renderer to its built-in ceiling —
  lighting technology (Voxel / ShadowMap / **Future** = per-pixel light + real
  dynamic shadows), Reflections, Atmosphere Density, and Depth of Field. Bloom
  uses a low threshold so the glow is actually visible. (A script can't do true
  ReShade / ray tracing — that needs an external injector — so this maxes out
  the engine's own lighting + post.) Default restores the snapshotted originals.
- **Fonts** — click a font (35+ options) to re-skin the hub, every other UI
  under `PlayerGui`, and chat (window + bubbles via `TextChatService`). Inert
  until you pick one, then per-root `DescendantAdded` listeners catch new UI —
  no polling loops. Covers **PlayerGui, CoreGui, and in-world Billboard/Surface
  GUIs** under Workspace (nameplates, signs…), so it reaches fonts the old pass
  missed. The font-list buttons keep their own font so each stays a live preview.
- **World** — time-of-day slider + Dawn/Noon/Sunset/Night buttons, camera FOV,
  atmosphere haze, a freeze-time toggle that genuinely holds the clock, a
  timelapse toggle (with speed) that **accelerates** the sun smoothly up to speed
  (and coasts back down) rather than snapping, and a **Fullbright** toggle that
  flattens lighting (snapshots + restores the originals).
- **Client** — local-only tools: **skin changer** — copies a user's avatar by
  username/ID fully client-side (pulls their appearance instances and parents
  them onto your character; `ApplyDescription` is server-only in many games) plus
  Stealth/Noob presets that recolour your parts directly, and a Ghost invis —
  **animation speed** (reads the Animator's tracks; with an
  option to sync to the World timelapse), **animation FastFlags**, an **FPS
  boost** that strips effects (+ FPS cap), and **anti-idle** to dodge the AFK
  kick. The FFlags / FPS cap / anti-idle paths use executor APIs and quietly
  no-op where unsupported (e.g. in Studio).
- **Fun** — pass-the-time toys: **emotes** (default Roblox emotes + a custom
  animation-id field), a bouncing **DVD logo**, and **Pong vs a robot** you
  play right in the panel.
- **Extras** — letterbox bars (+ size), hide nameplates/healthbars, **hide
  other players** (local-only, clean restore), hide game UI, and Reset All.

### Free Cam — controls

**Desktop**

| Action | Input |
|--------|-------|
| Toggle | `P` or the tab's **Enter / Exit Free Cam** button |
| Move | `W` `A` `S` `D` / arrows |
| Up / Down | `E` / `Q` |
| Look | Mouse (cursor locks to centre while active) |
| Boost / Slow | `Shift` / `Ctrl` |
| Speed | **Mouse scroll wheel** while flying (cursor's locked), or the **Move Speed** slider / on-screen Speed bar |
| Smooth flight | **Smooth Flight** toggle in the tab — adds momentum so the camera glides like on ice (Glide Smoothness slider) |

**Mobile**

| Action | Input |
|--------|-------|
| Toggle | Free Cam tab button, or the on-screen **Exit** button |
| Move | Drag anywhere on the **left half** — a joystick spawns under your thumb and trails it |
| Up / Down | ▲ / ▼ buttons |
| Look | Drag the **right half** of the screen |
| Speed | The **on-screen Speed bar** at the top while flying (or the tab slider) |

Purely client-side — it only moves your camera, never your character, and uses
the supported `SetCoreGuiEnabled` / `SetCore` / `GuiService` APIs to hide UI.
While the free cam is active, character controls are disabled via the
`PlayerModule` (and the root part anchored), so moving the joystick or pressing
WASD flies the camera **without walking your avatar around**. Both are restored
on exit.
