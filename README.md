# gfxCardStatus

**This is an independently maintained fork of [gfxCardStatus](https://github.com/codykrieger/gfxCardStatus) by [Cody Krieger](https://github.com/codykrieger).** It is a modernized menu-bar app (macOS 13+, universal binary, Sparkle 2, the opt-in rules below). It is **not affiliated with or supported by** Cody Krieger, the original author. Upstream is in maintenance mode and did not take this work. Issues, downloads, and updates for this copy belong in this repository.

- Original project: [github.com/codykrieger/gfxCardStatus](https://github.com/codykrieger/gfxCardStatus)
- Original website: [gfx.io](https://gfx.io). Donations there support Cody Krieger, the original author, not this fork.

The app name and bundle identifier are unchanged (`gfxCardStatus`, `com.codykrieger.gfxCardStatus`). See [Shared bundle identifier](#shared-bundle-identifier) before installing this over, or next to, the original app.

## Download

Install the latest build from **[GitHub Releases](https://github.com/derekgboyer/gfxCardStatus/releases/latest)**.

The first release is [v1.0.0](https://github.com/derekgboyer/gfxCardStatus/releases/tag/v1.0.0). The app inside that release reports version **2.5**, build **5510**. GitHub tag names and the version shown in the app are not the same number.

Sparkle checks this fork's appcast:

`https://github.com/derekgboyer/gfxCardStatus/releases/latest/download/appcast.xml`

That feed is the default for Xcode and `script/dist` builds, and for tag builds of this repository. Do not point a copy of this fork at the original project's update feed.

## Requirements

- macOS 13.0 (Ventura) or later
- **GPU switching** needs a dual-GPU Intel MacBook Pro
- Apple silicon: the universal build runs, but those Macs have one GPU. The app stays in the menu bar and the switching controls are disabled
- To build: Xcode 16 or later, and network access the first time the project opens so Xcode can fetch Sparkle

The app is a universal binary (`arm64` and `x86_64`). Debug builds the active architecture only. Release builds both.

## What it does

gfxCardStatus shows which GPU is active and can switch between integrated only, discrete only, and dynamic switching.

Every automatic feature below is **off until you turn it on**, except GPU history, which only records. With every automatic rule off, the app still forces Dynamic Switching at launch on a supported Mac, and it does not change GPUs when you plug in or unplug. Quitting still returns a supported Mac to Dynamic Switching.

## Opt-in features

### Power source

Turn it on from the status menu (**Use power source-based switching**) or **Preferences → Advanced**. On Battery and Plugged In each have their own choice: Integrated Only, Discrete Only, Dynamic Switching, or Don't Change.

The choice is saved in `~/Library/Preferences/com.codykrieger.gfxCardStatus-Preferences.plist` and applied when the power source changes. A mode you pick from the status menu, a keyboard shortcut, a URL, or a `--integrated`, `--discrete`, or `--dynamic` launch argument holds until the next settled power-source change, until you choose **Resume Automatic Rules**, or until you select a profile. Pause does not end that hold and does not change the GPU. Don't Change leaves the GPU alone and does not fall through to the launch or wake rule.

Integrated Only is not applied while an external display or an app is keeping the discrete GPU awake. The app posts a notification and does not call the mux again until the next evaluation.

The controls are disabled on Macs that cannot switch GPUs, and on the old 9400M/9600M machines that can only toggle between GPUs. An older preferences file that still has this feature turned on is reset to off once, so an upgrade does not start switching by itself.

"Load gfxCardStatus at startup" registers the app with `SMAppService`. macOS may ask you to approve it in **System Settings → General → Login Items & Extensions**.

### Rules

Preferences → Advanced has a section for each rule. The status menu adds Pause, Resume, Profiles, and GPU History on Macs that can switch.

One evaluation, first match wins:

1. **Manual override.** A status-menu choice, keyboard shortcut, launch argument, or `gfxcardstatus://` URL. It ends on the next settled power-source change, on Resume, or when a profile is selected.
2. **Pause.** Suppresses every automatic rule for one hour. It does not change the GPU and does not clear a manual hold. A pause that has not expired yet is still in effect after relaunch.
3. **Per-app.** While a chosen app is running, use the GPU it requests. Discrete wins if any matching app requests it.
4. **External display.** Discrete Only while a non-built-in display is connected.
5. **Battery threshold.** Integrated Only when the charge is known and below the percent you set (default 20). This can match on AC power too.
6. **Schedule.** The first range that contains the current minute. The end minute is not included. A range that passes midnight is allowed. An empty range never matches.
7. **Power source**, including Don't Change. Don't Change does not fall through.
8. **Launch or wake.** The launch default runs only at launch. The wake rule runs only on wake.

If nothing matches, the GPU is left as it is. Launch forces Dynamic Switching only when no rule handles launch and the Mac is not a legacy toggle-only machine. Quit still returns a supported Mac to Dynamic Switching.

### Integrated Only limitations

macOS will not switch to the integrated GPU while an external display is connected or while an application is using the discrete GPU. gfxCardStatus lists those apps and does not force the switch. Choosing **Why?** in that alert opens this section. The same limit applies to automatic rules: Integrated Only is skipped, a notification is posted, and the app waits for the next real change.

### Profiles

Profiles bundle the rules above: power source, per-app, battery threshold, external display, schedules, launch, wake, the notification app list, and the long-discrete alert. Shortcuts, the menu-bar GPU name, history, and pause are global.

The first time these rules are saved, gfxCardStatus stores your current settings as **Default** and adds two inactive examples, **Travel** and **Desk**. Choosing a profile saves the rules you had, loads the chosen snapshot, clears a manual hold and any pause, and applies once.

### Keyboard shortcuts

Set them in Preferences → Advanced. They use the system hotkey API, so they work without Accessibility access, and macOS can refuse a combination it already owns. Integrated Only from a shortcut, URL, or launch argument uses a notification instead of the status menu's dialog when the discrete GPU is busy, and it does not stick as a manual hold.

### Notifications, menu bar, and history

GPU change notifications already exist. **List apps using the discrete GPU** adds the dependency names to that notification, and to the long-on-battery alert, only while the checkbox is on. The long-on-battery alert is its own switch (default off, 30 minutes).

**Show the active GPU name in the menu bar** is off, so the single-letter icon stays. GPU history is on and does not change the GPU. Uncheck **Record GPU changes** to stop.

## Command line and URL scheme

`script/gfxcardstatus` talks to the running app with the `gfxcardstatus://` URL scheme:

```sh
script/gfxcardstatus integrated
script/gfxcardstatus discrete
script/gfxcardstatus dynamic
script/gfxcardstatus pause
script/gfxcardstatus resume
script/gfxcardstatus profile Travel
script/gfxcardstatus status
```

The same commands work as launch arguments: `--integrated`, `--discrete`, `--dynamic`, `--pause`, `--resume`, `--profile Travel`, and `--status`. `status` writes `~/Library/Application Support/gfxCardStatus/status.txt` because a menu-bar app cannot print to the terminal that opened the URL. The script waits briefly and prints that file.

## Build from source

1. Clone this repository.
2. Open `gfxCardStatus.xcworkspace` (or `gfxCardStatus.xcodeproj`). CocoaPods is no longer used. The workspace only contains the app project.
3. Wait for the Sparkle Swift package to resolve.
4. Select the **gfxCardStatus** scheme.
5. Build with ⌘B and run with ⌘R.

Debug builds are ad-hoc signed (`CODE_SIGN_IDENTITY = -`) with Hardened Runtime. Release builds use automatic signing and the development team already set on the target. The app is not sandboxed: GPU switching talks to the `AppleGraphicsControl` IOKit user client, and the dependency list reads other processes with `sysctl`.

GPU switching only works on a dual-GPU Intel MacBook Pro. On any other Mac the menu bar item stays up and the switching commands are hidden.

Local Xcode builds and `script/dist` embed this fork's Sparkle feed and public key. Passing `SPARKLE_FEED_URL` or `SPARKLE_PUBLIC_ED_KEY` to `xcodebuild` still overrides them. The tag workflow does that. Details, secrets, and how to cut a release are in [RELEASING.md](RELEASING.md).

`script/dist` is the local archive path. Its notarization step still uses the Apple ID and team recorded in that script, which are the original author's. Signed, notarized releases of **this** fork are the GitHub Actions tag builds in `RELEASING.md`.

## Shared bundle identifier

This fork keeps `com.codykrieger.gfxCardStatus` and the app name `gfxCardStatus`, the same as the original project. macOS treats them as one app:

- Preferences, Sparkle's user-defaults domain, the login item, and the `gfxcardstatus://` URL scheme are shared. Running both copies at once will fight over the GPU and those settings.
- An old `SUFeedURL` left in that domain by the original app (including the gfx.io beta feed) would make Sparkle ignore the feed in Info.plist. This fork removes only an upstream gfx.io or original-project feed at launch, then checks this repository's appcast. Any other feed you set yourself is left alone.
- Replacing one app with the other in `/Applications` is an update of the same bundle id, not a side-by-side install.

## License

Licensed under the New BSD License.

Copyright (c) 2010-2020, Cody Krieger
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:  
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.  
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.  
    * Neither the name of gfxCardStatus nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.  

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL CODY KRIEGER BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
