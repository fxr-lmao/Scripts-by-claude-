# Roblox Scripts

Roblox Luau scripts. Unless noted otherwise, each is a **LocalScript** meant for
`StarterPlayer > StarterPlayerScripts`.

## Index

| Script | Type | Description |
|--------|------|-------------|
| [`FreeCam.lua`](FreeCam.lua) | LocalScript | Cross-platform cinematic free camera. Detaches from your character and hides **all** UI (player + core/topbar/chat/backpack/health/leaderboard) for clean shots. Desktop (WASD + mouse) and full mobile (thumbstick, ▲/▼, drag-to-look, speed slider). Toggle with **P** or the on-screen button. |

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

While the free cam is active, character controls are disabled via the
`PlayerModule`, so moving the joystick (or pressing WASD) flies the camera
**without walking your avatar around**. Controls are restored on exit.
