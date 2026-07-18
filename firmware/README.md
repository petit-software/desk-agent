# DeskAgent RP2040 Firmware

This firmware targets the Waveshare RP2040-Matrix board and drives its 5x5
WS2812 matrix from GPIO 16. It exposes the DeskAgent AM1 protocol over USB CDC
and enforces the shared `64 / 255` brightness ceiling. Pixel bytes are emitted
in the board's RGB channel order, with the physical chain rotated 180 degrees
to match the board's upright USB orientation.

Build the tracked app resource with:

```sh
./scripts/build-firmware.sh
```

The script uses Raspberry Pi Pico SDK `2.3.0`, installs it into the user cache
when necessary, and copies the resulting UF2 to
`firmware/artifacts/DeskAgent.uf2`. CMake, Ninja, and the ARM embedded GCC
toolchain with Newlib must be available.

To flash from the macOS app, open **Matrix Simulator > Connected Device** and
choose **Flash Firmware**. Hold BOOT, press and release RESET, then release BOOT.
DeskAgent validates the bundled UF2, copies it to `RPI-RP2`, and verifies the
AM1 connection after the board restarts.
