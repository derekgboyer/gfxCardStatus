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

"Load gfxCardStatus at startup" registers the app with `SMAppService`. macOS
may ask you to approve it in **System Settings → General → Login Items &
Extensions**.

## Release archive

`script/dist` archives the app, notarizes it with `notarytool`, staples the
ticket, and prints a Sparkle 2 appcast item. Run it on a Mac that has the
notarization keychain item and the EdDSA signing key the script expects.
Sparkle 2 no longer uses the DSA signature.

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
