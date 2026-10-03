# Audio support

The Audio page targets the **QuadCast 2 S**, without changing the Mac's default
input/output devices. It pairs the microphone's input and headphone output by
USB device UID/serial so that separate microphones are not combined.

| Feature | Implementation / tested hardware availability |
| --- | --- |
| Microphone volume | Core Audio input volume, both channels. Reads device state every 500 ms; writes are read back, including hardware quantization. |
| macOS mute | Core Audio input mute. This is separate from the firmware's tap-to-mute state. |
| Tap-to-mute status | Listens for absolute vendor HID mute events. Initial state remains unknown until an event; it is never guessed from macOS mute or silence. The event format is documented for QuadCast 2; reception on 2 S still needs hardware verification. |
| Headphone volume | Capability-aware Core Audio output volume. **Not exposed by the currently tested 2 S firmware/driver.** Use the multifunction knob. |
| Monitor / playback mix | **Not exposed by the currently tested firmware/driver.** Use monitor-mix mode on the knob. A Core Audio monitoring-volume control, when exposed, adjusts direct monitoring independently of playback volume. |
| Polar patterns | Four pattern descriptions; software selection only when the driver exposes all four named sources. **Not exposed by the currently tested firmware/driver.** Hold the knob for two seconds, then turn it; the LED ring indicates the pattern. |
| Level meter | Opt-in capture of this microphone, stereo RMS/peak, silence floor −60 dBFS, clipping indication. No default microphone fallback. |
| Microphone test | Up to five seconds of stereo audio, in memory. Playback uses the Mac's selected output after capture stops; leaving Audio, disconnecting, or quitting discards the test. |

On the connected device examined during development, macOS exposes two audio
devices: input has per-channel volume and master mute; output has master mute
but no volume control. Neither advertises monitoring or named input sources.
The USB descriptors advertise output volume, but that alone is insufficient to
create a working macOS control: the active driver does not expose it.

## Remaining vendor protocol work

The audio device is USB `03f0:0d84`; the lighting controller is `03f0:02b5`.
The audio HID descriptor includes input/output report `0x77` (64 bytes).
The Linux HyperX driver documents an absolute mute event `77 06 00/01` for
**QuadCast 2**, not a verified writable 2 S audio command.

Implementing headphone volume, monitor mix, remote pattern selection and an
initial hardware mute query requires verified 2 S command captures or protocol
documentation. A useful NGENUITY USBPcap capture would include application launch,
each control changed individually in both directions, all four patterns,
tap-to-mute and unmute, and knob changes. Do not brute-force commands or treat
an acknowledged packet as proof that it changed the intended setting.

References:

- [HyperX QuadCast 2 S](https://hyperx.com/products/hyperx-quadcast-2-s-usb-microphone)
- [HyperX NGENUITY](https://hyperx.com/pages/ngenuity)
- [Linux HyperX mute-event driver](https://github.com/torvalds/linux/blob/master/drivers/hid/hid-hyperx.c)
- [Apple Core Audio audio-device properties](https://developer.apple.com/documentation/coreaudio/audio-device-properties)

Core tests cover stereo meter accuracy, clipping/non-finite input, bounded
recordings, WAV encoding, capture privacy, and strict vendor event parsing. UI
tests use a fake device and never request audio/HID permissions; they cover
supported and unavailable controls and stopping capture when leaving the page.
