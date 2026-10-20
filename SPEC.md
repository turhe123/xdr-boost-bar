# XdrBoostBar — specification

**Tagline:** Unlock the extra HDR headroom of your MacBook Pro or XDR display for brighter everyday content with a slider.

**Category:** Display & Brightness

**Inspired by (paid):** Vivid ($15 one-time)

**Frameworks:** SwiftUI, AppKit, MetalKit, QuartzCore, CoreGraphics, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: Vivid raises the usable brightness of mini-LED Mac displays beyond the usual sustained level by using the extended dynamic range headroom, and it is sold for about fifteen dollars one time after a free trial. Launch coverage from several Mac news sites described it as nearly doubling perceived brightness outdoors, and users still recommend it for sunlight use, which shows steady demand.

Our clean-room version: a menu bar slider from zero to one hundred percent that sets how much extra brightness to add on top of the system level. A global toggle hotkey switches the boost on and off. An option limits the boost automatically when the Mac runs on battery or when the display reports serious thermal pressure. A per-display list lets the user enable the boost only on supported screens. Keep it to roughly three hundred fifty lines.

UI spec: a MenuBarExtra with a sun icon, showing a popover with an Enabled switch, a Boost slider, a display picker, a Battery saver checkbox with a threshold percent field and a launch at login checkbox. Keyboard shortcut: Control Option B toggles the boost. States: Off, On with percentage, and Unsupported, in which the popover says that no display with extended dynamic range headroom was found and disables the controls. A short note explains that the boost raises battery use and heat.

Technical approach: for every NSScreen check maximumPotentialExtendedDynamicRangeColorComponentValue greater than one to detect supported displays. Place a one-pixel-sized, click-through, borderless window per display at the highest window level, hosting a CAMetalLayer or MTKView with wantsExtendedDynamicRangeContent set true and a float16 pixel format with the extended linear display P3 color space. The layer renders a bright value that forces the display pipeline into HDR mode, and a screen-sized overlay with a multiply or additive compositing filter, applied through the compositingFilter on the layer, scales the rest of the desktop up by the chosen factor. Because this relies on compositing behavior, a fallback is a small gamma-table adjustment through CGSetDisplayTransferByFormula that stretches the output curve. Read power source using ProcessInfo thermalState and the low power mode flag, and the IOKit power source API for battery state, but IOKit is optional. Persist settings with AppStorage and register login item with SMAppService.

Edge cases: when a display is unplugged or the Mac sleeps, tear down and rebuild the overlay windows from the screen parameter change notification. If the user changes the system brightness, keep the boost relative. If the thermal state reaches serious or critical, ramp the boost down smoothly over a second and show a notice. Restore the gamma tables on quit with CGDisplayRestoreColorSyncSettings. Warn that screenshots and screen recordings may show a brightened look. Do not claim support on external non-HDR monitors.
