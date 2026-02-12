# QuadcastRGB
# About
The program (or driver, if you wish) allows setting the RGB lights of HyperX
*Quadcast S and Duocast* just like NGenuity does. It is supposed to work on all
Unix-like systems. The Linux and MacOS versions have been tested and work as
expected.

Available modes are *solid, blink, cycle, wave, lightning, and pulse*. The
program runs as a daemon (except the MacOS version), kill it, or unplug the mic
to stop.

## Features:
- *free & open source (GPL-2.0-only)*
- *works on Unix-like OSes*
- *cli*
- *daemon*

## Things yet to be done:
- *self-contained static compilation (without libusb)*
- *the foreground option (-f and --foreground)*
- *properly test FreeBSD*
- *visualizer mode (i.e. VU meter)*
- *save option*
- *multiple mics support*

## Examples:
```bash
# Default solid color (#f20000, red) for the whole micro:
quadcastrgb solid 
# Random blinking colors:
quadcastrgb blink
# Default cycle (rainbow) mode for the whole micro:
quadcastrgb -a cycle 
# Purple color for the upper part and yellow for the lower:
quadcastrgb -u solid 4c0099 -l solid ff6000 
# Default cycle mode for the upper diode with 50% brightness and yellow lightning for the lower:
quadcastrgb -u -b 50 cycle -l lightning ff6000 
```

# Install
## Arch-based distro
*quadcastrgb* is available in the AUR.
### Install with yay
```bash
yay -S quadcastrgb
```
### Build on your own
```bash
mkdir quadcastrgb && cd quadcastrgb
wget https://gitlab.com/Ors1mer/QuadcastRGB/-/raw/main/aur/PKGBUILD
makepkg -sri # build and install
cd .. && rm -rf quadcastrgb # clean-up
```

## Debian-based distro
Simply download it and install:
```bash
wget https://ors1mer.xyz/downloads/quadcastrgb-1.0.4-2-amd64.deb
dpkg -i quadcastrgb-1.0.4-2-amd64.deb
```
Alternatively, it is possible to make a deb package of your own:
```bash
git clone https://gitlab.com/Ors1mer/QuadcastRGB.git
cd QuadcastRGB
make debpkg # build the package with dpkg
dpkg -i packages/deb/quadcastrgb-1.0.4-2-amd64.deb # install
```

## RPM-based distro
Everything is pretty much the same as for deb. Simply download and install:
```bash
wget https://ors1mer.xyz/downloads/quadcastrgb-1.0.4-2.x86_64.rpm
rpm -ivh quadcastrgb-1.0.4-2.x86_64.rpm
```
Or build the package from source:
```bash
git clone https://gitlab.com/Ors1mer/QuadcastRGB.git
cd QuadcastRGB
make rpmpkg # build the package in ~/rpmbuild/
rpm -ivh quadcastrgb-1.0.4-2.x86_64.rpm
```

## macOS

### QuadCast 2S GUI App

A native macOS menu bar app for controlling the HyperX QuadCast 2S RGB lighting.
Requires macOS 26 (Tahoe) and Homebrew.

#### Install dependencies
```bash
brew install hidapi pkg-config
```

#### Build from source
```bash
xcodebuild build \
  -project QuadcastRGBApp/QuadcastRGBApp.xcodeproj \
  -scheme QuadcastRGBApp \
  -configuration Release \
  -derivedDataPath .build/DerivedData-release
```
The built app is at `.build/DerivedData-release/Build/Products/Release/QuadcastRGBApp.app`.
Copy it to `/Applications` to install.

#### Package as DMG
For local use (ad-hoc signed, no notarization):
```bash
./QuadcastRGBApp/scripts/package-dmg.sh --skip-notarize
```

For distribution (requires a Developer ID Application certificate):
```bash
# One-time: store notarization credentials in Keychain
xcrun notarytool store-credentials AC_PASSWORD \
  --apple-id your@email.com --team-id YOUR_TEAM_ID

# Build, sign, create DMG, notarize, and staple
APPLE_ID=your@email.com ./QuadcastRGBApp/scripts/package-dmg.sh
```

The script auto-detects your Developer ID certificate, deep-signs with
hardened runtime and entitlements, creates a compressed DMG with a
drag-to-Applications layout, submits to Apple for notarization, and
staples the ticket.

Output: `QuadcastRGBApp.dmg` in the project root.

### CLI (QuadCast S / DuoCast)

Install dependencies:
```bash
brew install libusb hidapi pkg-config
```

Build and install:
```bash
make install
```

Or download a prebuilt binary for your architecture (Intel or ARM) and run:
```bash
chmod 711 quadcastrgb
xattr -dr com.apple.quarantine quadcastrgb
./quadcastrgb solid
```

## Compiling from source
If you are lucky, this should be enough:
```bash
make install # linux
gmake install OS=freebsd # freebsd
make install OS=macos # mac
```
Specify *BINDIR_INS* and *MANDIR_INS* for *make* if you want to change the
install locations.

# FAQ
## Problem 1: make failed
Check the dependencies:
- gcc v12.2.0 OR clang v14.0.6 (most versions should do fine)
- libusb-1.0 v1.0.26 or newer
- glibc or any other standard C library

## Problem 2: command not found
Check the $PATH and manpath. The program follows XDG specifications, so the
binary is stored in $HOME/.local/bin (should be in $PATH) and the man is in
$HOME/.local/share/man (should be in $MANPATH). It is possible to move them,
of course.

## Problem 3: couldn't open the microphone
Check the error code. If it is 4, try running the program under superuser
privileges. If that was the problem, you should eventually create a dev rule
for the microphone to allow certain users access to it.

## How to create the udev rule
Firstly, check what is the VendorID:ProductID of your mic e. g. like this:
```bash
$ lsusb
Bus 001 Device 007: ID 0951:171f Kingston Technology HyperX QuadCast S # this is what you're looking for
Bus 001 Device 006: ID 0951:171d Kingston Technology HyperX QuadCast S
```
It must be either 0951:171f, 03f0:0f8b, 03f0:028c, 03f0:048c, 03f0:068c,
or 03f0:098c (if it isn't, contact me, the author, I'll add support for your
IDs).

Let's proceed to the rule creation:
```bash
# Here the rules are stored:
cd /etc/udev/rules.d
# Do under superuser:
vi 10-quadcast-perm.rules
```
Write this line, save & exit (:wq):
```bash
SUBSYSTEMS=="usb", ATTRS{idVendor}=="<THE_VENDOR_ID>", ATTRS{idProduct}=="<THE_PRODUCT_ID>", MODE="0660", GROUP="hyperrgb"
```
Now the microphone is accessible for the group "hyperrgb". Add your user to the
group and it's done.

## Problem 4: launching the program a second time does nothing
Probably, the previous instance is still running. Kill it
with *kill* or *killall*.

## How to end the program
Simply kill the process by name:
```bash
killall quadcastrgb
```

## Problem 5: "HyperX Quadcast S isn't connected" even though it is
Chances are you have a new revision of the mic that has unsupported
VendorID:ProductID.

Currently supported IDs:
- 0951:171f
- 03f0:0f8b
- 03f0:028c
- 03f0:048c
- 03f0:068c
- 03f0:098c

If you have different IDs (check it with *lsusb*, for example), contact the
author; I'll add the support very quickly.

When reporting the issue, provide the detailed output about Quadcast S devices
if possible:
```bash
lsusb -vd 'VendorID:ProductID'
```
