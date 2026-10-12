<h1 align="center">Clawd Desktop Pet</h1>

<p align="center">
  <b>English</b> · <a href="README.de.md">Deutsch</a>
</p>

<p align="center">
  A tiny pixel companion that lives on your Windows taskbar.<br>
  He wanders around, naps, drinks coffee – and types along whenever you type.
</p>

<p align="center">
  <img src="docs/poses.png" alt="Clawd in sixteen different poses" width="720">
</p>

> **Unofficial fan project.** Not affiliated with, endorsed by, or supported by Anthropic. "Claude" and the Clawd mascot belong to Anthropic.

## Features

**He keeps himself busy**

- Walks along the taskbar, hops, dances, waves and stretches
- Naps (more often at night), drinks coffee, reads a book, puts on sunglasses
- Follows your mouse pointer with his eyes and blinks
- **Lands on your windows:** drop or throw him onto a window and he stands and walks on its top edge – and falls down when you drag the window away

**He reacts to you**

- **You type → he types.** Clawd pulls out a laptop and taps a key for every key you press
- **You're away for 2 minutes → he falls asleep**
- **You come back → he wakes up and waves**
- **Sound is playing → he dances**, bouncing harder the louder it gets

**He grows with you**

- **Hunger:** he gets hungry over time and shows a little cookie bubble when he wants food
- **Levels:** feeding and petting earn XP. New levels unlock tricks (flip, juggling, balloon ride, wall climbing), colors and outfits
- **Outfits:** beanie, party hat, headphones, top hat and crown, picked from the right-click menu – plus a flower as a thank-you when you open the feedback form

**You can play with him**

| Action | What happens |
| --- | --- |
| Click | Pet him (hearts!) – or wake him up |
| Double-click | Flip |
| Drag and release | Pick him up and throw him – he bounces, and gets dizzy after a hard landing |
| Right-click | Menu: level and hunger, feed, activities, outfit, color, size, language, speech bubbles, dance to music, start with Windows, send feedback |
| Tray icon | Show / hide, bring him back to the centre, quit |

More tricks are waiting in the right-click menu – some of them only once he has reached the right level.

## Getting started

**Download:** grab `ClawdPet.exe` from the [Releases](../../releases) page and double-click it. No installer, no dependencies – it is a single small file.

On first launch a welcome window lets you pick the **language (English / Deutsch)**, size and color:

<p align="center">
  <img src="docs/setup-en.png" alt="Welcome window with language, size and color options" width="320">
</p>

Everything can be changed later by right-clicking Clawd.

> Windows SmartScreen may warn about an unknown publisher, because the file is not code-signed. Choose "More info" → "Run anyway", or build it yourself from source.

## macOS

There is a Mac version too, written in Swift (folder [`mac`](mac)). It needs macOS 12 or newer and runs on Apple silicon and Intel.

**Download:** [ClawdPet-mac.zip](../../raw/mac-ci/ClawdPet-mac.zip) – always the latest automatic build. Unzip it and move `ClawdPet.app` wherever you like.

The app is not signed with a paid Apple developer account, so macOS blocks the first start. Right-click the app → **Open** → **Open**. On newer macOS versions: try to open it once, then go to System Settings → Privacy & Security → **Open Anyway**.

What is different on the Mac:

- Clawd stands on top of the Dock and has an icon in the menu bar instead of the tray
- Menus and the welcome window use the native macOS look
- No dancing to music (macOS does not hand out the speaker level)
- Everything else is the same: windows as platforms, typing along, hunger, levels, outfits, demo mode

Build it yourself on a Mac with the Xcode command line tools: `bash mac/build.sh`

> The Mac version is built and started automatically on GitHub's Macs, and the result is checked from screenshots. Clicking, dragging and throwing have not been tried by a human on a real Mac yet – reports are welcome.

## Build from source

Nothing to install – the script uses the C# compiler that ships with Windows (.NET Framework 4.x):

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1
.\ClawdPet.exe
```

The whole app is one file, [`ClawdPet.cs`](ClawdPet.cs).

## Demo mode

Want to record a video? Right-click Clawd → **Demo mode** (or start with `ClawdPet.exe --demo`). He then plays all 17 activities one after another in a fixed loop, a few seconds each, and ignores your keyboard while doing so.

## Privacy

To type along, the app asks Windows *whether* a key is currently pressed (`GetAsyncKeyState`). It never looks at *which* key, and nothing is stored or sent anywhere – the app does not use the network at all. Some antivirus tools flag this kind of check anyway.

For dancing, the app reads how loud your speakers currently are – just the level, no audio is recorded. To stand on windows, it reads the position of your open windows, not their content.

The right-click menu has a frosted-glass look. For that, the app takes a snapshot of the small screen area behind the menu at the moment it opens and blurs it. The snapshot only lives in memory while the menu is open.

Settings and progress live in `%AppData%\ClawdPet\settings.txt`.

## Feedback

Found a bug or have a wish? Right-click Clawd → **Send feedback…**. That opens a short form in your browser – no account needed. The app itself still sends nothing; only what you type into the form is submitted, together with the app version and your system version.

## Good to know

- Windows 10 / 11
- Clawd stays on the primary monitor
- Uses a few percent of one CPU core while running

## Contributing

Ideas, bug reports and pull requests are welcome – new activities and more languages especially.

## License

[MIT](LICENSE) for the code. The Clawd character and the Claude name remain the property of Anthropic.
