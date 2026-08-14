# Design — Mac Native Local ASR App

## Design Intent

The user must know — at a glance, from any app — whether the dictation tool is ready, recording, or processing, and whether their words landed. This is a utility, not a product. It should feel like a system extension, not an application.

## Physical Product Analogy

A hardware push-to-talk microphone with a status LED. You press a button, a light turns red, you speak, you press again, the light turns yellow, then the text is in your clipboard. No screen, no menus, no settings visible unless you go looking for them. Every visual element must answer: "would a physical dictation microphone have this?"

## Aesthetic Direction

**Amplify**: utilitarian clarity. This is a tool that sits in the menu bar and gets out of the way.

**Prohibit**:
- No glass morphism, no translucency effects, no gradients
- No decorative illustrations or app icon animations
- No cards or card-like containers in the dropdown
- No gray-on-gray text (use system label colors)
- No window chrome beyond the minimal settings panel
- No onboarding screens — permissions are requested on first action, not in a wizard

## Visual Specification

### Menu Bar Icon

Template image (SF Symbol) that changes by state. Template images adapt to light/dark mode automatically.

| State | Icon | Meaning |
|---|---|---|
| Loading | `waveform.circle` (dimmed) | Model loading, not ready |
| Idle | `waveform.circle` (normal) | Ready to record |
| Recording | `waveform.circle.fill` (red tint) | Recording in progress |
| Processing | `waveform.circle.badge.ellipsis` | Transcribing, please wait |
| Error | `exclamationmark.triangle.fill` (red tint) | Something went wrong |

Red/yellow tinting uses `NSImage.tint(with:)` — the image stays template for dark mode but gets a colored tint overlay for recording/error states. No animation (template images don't animate well, and a flashing menu bar icon is annoying).

### Dropdown Menu

Standard macOS dropdown menu (`.menu` style). No custom views, no SwiftUI canvas, no special rendering.

```
┌─────────────────────────────────────┐
│ Ready                          ●    │  ← status row with colored dot
│                                     │
│ Last: 你好世界，this is a test       │  ← truncated last transcript
│                                     │
│ ─────────────────────────────────── │
│                                     │
│ Settings…                    ⌘,     │
│ Quit                          ⌘Q    │
└─────────────────────────────────────┘
```

Status row shows:
- Loading: "Loading model…" (gray dot)
- Idle: "Ready" (green dot)
- Recording: "Recording…" (red dot, pulsing not needed — the menu bar icon already shows red)
- Processing: "Transcribing…" (yellow dot)
- Error: "Error: <message>" (red dot, message truncated)

Last transcript row:
- Click copies to clipboard again
- Truncated to fit menu width (~50 characters)
- If empty: row is hidden, not shown as "No transcripts yet"

### Settings Window

Small panel, not a full window. Fixed size, no resizing.

```
┌─────────────────────────────────────────┐
│  Mac Local ASR Settings                  │
│                                          │
│  Hotkey:          [⌘⇧Space]    [Record]   │
│                                          │
│  ASR Bridge:      [/path/to/script.py]   │
│  Model Path:      [/path/to/model]       │
│                                          │
│  Status: Model loaded ✓                 │
│                                          │
│              [Close]                     │
└─────────────────────────────────────────┘
```

Three controls. No tabs, no advanced section, no hidden settings.

Hotkey recorder uses `KeyboardShortcuts.Recorder` (standard SwiftUI view from the SPM package).

Bridge path and model path use text fields with browse buttons (`NSOpenPanel`).

Status line shows model load state with a checkmark or error.

### Bilingual Support

All user-visible strings have English and Simplified Chinese versions, selected by system locale:

| English | 简体中文 |
|---|---|
| Ready | 就绪 |
| Recording… | 录音中… |
| Transcribing… | 转写中… |
| Loading model… | 模型加载中… |
| Error: | 错误： |
| Last: | 上次： |
| Settings… | 设置… |
| Quit | 退出 |
| Copied to clipboard | 已复制到剪贴板 |
| Microphone access required | 需要麦克风权限 |
| Hotkey | 快捷键 |
| ASR Bridge Path | ASR 引擎路径 |
| Model Path | 模型路径 |
| Status | 状态 |
| Model loaded | 模型已加载 |
| Close | 关闭 |

Use `String(localized:)` with `.xcstrings` catalog. Default locale: English. Chinese translation in the same catalog.

## States Coverage

| State | Menu bar icon | Dropdown status | Last transcript row |
|---|---|---|---|
| Loading | dimmed waveform | "Loading model…" | hidden |
| Idle | normal waveform | "Ready" | shown if exists |
| Recording | red filled waveform | "Recording…" | shown if exists (previous) |
| Processing | waveform with ellipsis badge | "Transcribing…" | shown if exists (previous) |
| Error | red triangle | "Error: <msg>" | shown if exists (previous) |
| No bridge configured | dimmed waveform | "Error: ASR bridge not configured" | hidden |
| No model path | dimmed waveform | "Error: Model path not set" | hidden |
| Microphone denied | red triangle | "Error: Microphone access denied" | hidden |
| Bridge crashed | red triangle | "Error: ASR engine crashed. Restarting…" | hidden |
| Bridge restart failed | red triangle | "Error: ASR engine failed to start" | hidden |

## Implementation Contract

- **Component sources**: all new — this is a standalone app, no design system import
- **Colors**: system colors only — `NSColor.systemRed`, `NSColor.systemYellow`, `NSColor.systemGreen`, `NSColor.labelColor`, `NSColor.secondaryLabelColor`. No custom color assets.
- **Typography**: system font (SF Pro) at default sizes. No custom fonts.
- **Spacing**: standard macOS menu spacing. No custom padding values.
- **Dark mode**: template images + system colors handle this automatically. No manual dark mode handling.

## Acceptance Screenshots

After implementation, capture:
1. Menu bar with idle icon (light mode)
2. Menu bar with recording icon (red tint)
3. Dropdown open showing "Ready" status
4. Dropdown open showing "Recording…" status
5. Settings window
6. Same 1-5 in dark mode

## Lesson

(to be captured after implementation)