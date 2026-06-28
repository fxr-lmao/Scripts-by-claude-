# Roblox Scripts

Roblox Luau scripts. Unless noted otherwise, each is a **LocalScript** meant for
`StarterPlayer > StarterPlayerScripts`.

## Index

| Script | Type | Description |
|--------|------|-------------|
| [`FreeCam.lua`](FreeCam.lua) | LocalScript | Cross-platform cinematic free camera. Detaches from your character and hides **all** UI (player + core/topbar/chat/backpack/health/leaderboard) for clean shots. Desktop (WASD + mouse) and full mobile (thumbstick, ▲/▼, drag-to-look, speed slider). Toggle with **P** or the on-screen button. |
| [`CinematicHub.lua`](CinematicHub.lua) | LocalScript | All-in-one cinematic tools hub — one floating button opens a tabbed, exploit-hub-style panel for **Free Cam**, **Shaders** (Bloom/Blur/DepthOfField/ColorCorrection/SunRays presets: Cinematic, Noir, Warm, Cold, Dreamy, Horror, plus manual sliders), **Fonts** (re-skins the hub, every other UI in the game, *and* chat — window + bubbles), **World** (time of day, FOV, atmosphere haze), and **Extras** (letterbox bars, hide nameplates/healthbars, reset-all). Everything is client-side and visual only — no exploits. |

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

## CinematicHub.lua — controls

| Action | Input |
|--------|-------|
| Open / close hub | Drag-anywhere **🎬 Cinematic** button, or press **`\`** (backquote) |
| Toggle Free Cam directly | `P` |

Tabs: **Free Cam** (same controls as `FreeCam.lua`), **Shaders** (preset buttons +
Bloom/Blur/Saturation/Contrast sliders), **Fonts** (click a font — it re-skins the
hub, every other UI under `PlayerGui`, and chat: both the chat window and bubble
chat, via `TextChatService`'s font config so there's no per-frame scanning),
**World** (time of day, camera FOV, atmosphere haze, freeze-time toggle), and
**Extras** (toggleable letterbox bars with a size slider, hide nameplates/
healthbars for clean shots, and a "Reset All" button).

Font changes are applied with a single one-shot scan of existing UI plus one
persistent `DescendantAdded` listener for anything spawned afterward — no
polling loops, so it won't add frame-rate overhead.

Run either `FreeCam.lua` **or** `CinematicHub.lua` — the hub already includes
free cam, so you don't need both.
