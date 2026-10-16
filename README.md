# gfxCardStatus

by Cody Krieger

gfxCardStatus is a menu bar app for dual-GPU Intel MacBook Pros. It shows which
GPU is active and can switch between integrated only, discrete only, and
dynamic switching.

On Apple silicon, and on any other Mac without switchable GPUs, the app still
launches. Switching controls are disabled and the status item explains that
GPU switching does not apply.

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 16 or later. A current Xcode is the intended toolchain.
- Network access the first time you open the project, so Xcode can fetch Sparkle

The app is a universal binary (`arm64` and `x86_64`). Debug builds the active
architecture only. Release builds both.

## Build and run

1. Clone this repository.
2. Open `gfxCardStatus.xcworkspace` (or `gfxCardStatus.xcodeproj`). CocoaPods is
   no longer used. The workspace only contains the app project.
3. Wait for the Sparkle Swift package to resolve.
4. Select the **gfxCardStatus** scheme.
5. Build with ⌘B and run with ⌘R.

Debug builds are ad-hoc signed (`CODE_SIGN_IDENTITY = -`) with Hardened Runtime.
Release builds use automatic signing and the development team already set on
the target. The app is not sandboxed: GPU switching talks to the
`AppleGraphicsControl` IOKit user client, and the dependency list reads other
processes with `sysctl`.

GPU switching only works on a dual-GPU Intel MacBook Pro. On any other Mac the
menu bar item stays up and the switching commands are hidden.

## Power source-based switching

The feature is off until you turn it on. With every automatic rule off,
gfxCardStatus still forces Dynamic Switching at launch, and it does not change
GPUs when you plug in or unplug.

Turn it on from the status menu (**Use power source-based switching**) or from
**Preferences → Advanced**. On Battery and Plugged In each have their own
choice:

- Integrated Only
- Discrete Only
- Dynamic Switching
- Don't Change

The choice is saved in the gfxCardStatus preferences plist
(`~/Library/Preferences/com.codykrieger.gfxCardStatus-Preferences.plist`) and
applied when the power source changes. gfxCardStatus watches for that with
IOKit (`IOPSNotificationCreateRunLoopSource`).

A mode you pick from the status menu, a keyboard shortcut, a URL, or a
`--integrated`, `--discrete`, or `--dynamic` launch argument, holds until the
next settled power-source change, until you choose **Resume Automatic Rules**,
or until you select a profile. Pause does not end that hold and does not
change the GPU. Turning the power-source feature on, or editing the choice for
the power source you are on now, applies immediately. Don't Change leaves the
GPU alone and does not fall through to the launch or wake rule. Quitting still
returns a supported Mac to Dynamic Switching.

The rest of the automatic rules, and the order they run in, are below.

Integrated Only is not applied while an external display or an app is keeping
the discrete GPU awake. gfxCardStatus posts a notification and does not call
the mux again until the next evaluation. With only this power-source rule
turned on, that next evaluation is a power-source change or an edit to the
current rule, not a display change.

The status menu shows the current power source. While a manual choice is
holding, that line is marked "manual".

The controls are disabled on Macs that cannot switch GPUs, and on the old
9400M/9600M machines that can only toggle between GPUs. An older preferences
file that still has this feature turned on is reset to off once, so an
upgrade does not start switching by itself.

"Load gfxCardStatus at startup" registers the app with `SMAppService`. macOS
may ask you to approve it in **System Settings → General → Login Items &
Extensions**.

## Automatic rules

Every rule is off until you turn it on, except GPU history, which only records.
Preferences → Advanced has a section for each one. The status menu adds Pause,
Resume, Profiles, and GPU History on Macs that can switch. On Macs that cannot
switch, and on 9400M/9600M machines that can only toggle, those controls are
disabled and the app still launches. The menu-bar name and history checkboxes
stay available.

One evaluation, first match wins:

1. **Manual override.** A status-menu choice, keyboard shortcut, launch
   argument, or `gfxcardstatus://` URL. Automatic rules do not run while it
   holds. It ends on the next settled power-source change, on Resume, or when
   a profile is selected. Editing the live power-source rule for the source
   you are on, or turning that feature off, also ends it.
2. **Pause.** Suppresses every automatic rule for one hour. It does not change
   the GPU and does not clear a manual hold. Resume clears both, then applies
   the rules. A pause that has not expired yet is still in effect after relaunch.
3. **Per-app.** While a chosen app is running, use the GPU it requests.
   Discrete wins if any matching app requests it. Otherwise Integrated Only.
4. **External display.** Discrete Only while a non-built-in display is connected.
5. **Battery threshold.** Integrated Only when the charge is known and below
   the percent you set (default 20). This can match on AC power too.
6. **Schedule.** The first range that contains the current minute. The end
   minute is not included. A range that passes midnight is allowed. An empty
   range (start equal to end) never matches. Checks are about every 30 seconds,
   and also when the clock changes.
7. **Power source**, including Don't Change. Don't Change does not fall through.
8. **Launch or wake.** The launch default runs only at launch. The wake rule
   runs only on wake. Higher rules win over both.

If nothing matches, the GPU is left as it is. gfxCardStatus does not call the
mux again when the GPU is already in the requested mode, and a GPU-change
notification does not apply the rules again, so a switch cannot loop.

Integrated Only is not applied while an external display or an app is holding
the discrete GPU on, for every rule. gfxCardStatus posts a notification and
does not retry until the next real change (a new app, display, power source,
schedule, wake, or an edited rule). With only the power-source rule turned on,
a blocked attempt is still not retried on a display change.

Launch forces Dynamic Switching only when no rule handles launch and the Mac
is not a legacy toggle-only machine. Per-app, the display rule, the battery
threshold, a schedule, power-source switching, or the launch default each
count. The wake rule does not. Turning per-app on, even with an empty app
list, skips that force. Quit still returns a supported Mac to Dynamic Switching.

### Profiles

Profiles bundle the rules above: power source, per-app, battery threshold,
external display, schedules, launch, wake, the notification app list, and the
long-discrete alert. Shortcuts, the menu-bar GPU name, history, and pause are
global.

The first time these rules are saved, gfxCardStatus stores your current
settings as **Default** and adds two inactive examples:

- **Travel** — power-source switching on, Integrated Only on battery, Dynamic
  Switching when plugged in, Integrated Only below 30%.
- **Desk** — power-source switching on, Dynamic Switching on battery, Discrete
  Only when plugged in, Discrete Only while an external display is connected.

Choosing a profile copies your current rules back into the one that was
active, loads the chosen snapshot, clears a manual hold and any pause, and
applies once. Names used from a script are `Default`, `Travel`, and `Desk`.

### Keyboard shortcuts

Set them in Preferences → Advanced. They use the system hotkey API, so they
work without Accessibility access, and macOS can refuse a combination it
already owns. Integrated Only from a shortcut, URL, or launch argument uses a
notification instead of the status menu's dialog when the discrete GPU is busy,
and it does not stick as a manual hold.

### Notifications, menu bar, and history

GPU change notifications already exist. **List apps using the discrete GPU**
adds the dependency names to that notification, and to the long-on-battery
alert, only while the checkbox is on. The long-on-battery alert is its own
switch (default off, 30 minutes). It counts whenever the discrete GPU is
driving the display, including during Dynamic Switching, and it is shown even
if GPU change notifications are off.

**Show the active GPU name in the menu bar** is off, so the single-letter icon
stays. Smart icons apply only while the name is hidden.

GPU history is on and does not change the GPU. It records the time, the mode,
and the app or rule that caused the change, including a blocked Integrated Only
attempt and changes gfxCardStatus did not request. The latest entries are in
the status menu. Uncheck **Record GPU changes** to stop.

### Scripts

`script/gfxcardstatus` talks to the running app with a URL scheme:

```sh
script/gfxcardstatus integrated
script/gfxcardstatus discrete
script/gfxcardstatus dynamic
script/gfxcardstatus pause
script/gfxcardstatus resume
script/gfxcardstatus profile Travel
script/gfxcardstatus status
```

The same commands work as launch arguments: `--integrated`, `--discrete`,
`--dynamic`, `--pause`, `--resume`, `--profile Travel`, and `--status`.
`--integrated` does not switch, and does not become a manual hold, while the
discrete GPU is busy. `status` writes
`~/Library/Application Support/gfxCardStatus/status.txt` because a menu-bar
app cannot print to the terminal that opened the URL. The script waits briefly
and prints that file.

## Release archive

Pushing a `v*` tag (for example `v2.5`) runs `.github/workflows/release.yml`.
That job builds the universal Release app, signs and notarizes it when the
Actions secrets are set, and uploads a zip, a DMG, source archives, and a
Sparkle appcast to the GitHub release. Pull requests and branch pushes run
`.github/workflows/build.yml`. The secrets, the EdDSA key, and the tag steps
are in `RELEASING.md`.

`script/dist` is the local path. It archives the app, notarizes it with
`notarytool`, staples the ticket, and prints a Sparkle 2 appcast item. Run it
on a Mac that has the notarization keychain item and the EdDSA signing key the
script expects. Sparkle 2 no longer uses the DSA signature.

Xcode and `script/dist` still use `https://gfx.io/appcasts/release.xml`
(`testing.xml` when `SU_FEED_CHANNEL` is `testing` or `beta`). The tag
workflow passes its own feed URL, so the app it publishes checks that
repository's GitHub release appcast.

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
