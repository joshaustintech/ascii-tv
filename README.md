# ascii-tv

ASCII animations for Apple TV.

The app shows an endlessly rotating ASCII globe. The day/night line follows the real sun, your own labelled
places are marked on it, and an Apple Music playlist of your choice loops in the background.

## Run it

```sh
./run.sh
```

Builds the app and launches it in the Apple TV 4K simulator. For 1080p output:

```sh
DEVICE="Apple TV 4K (4th generation) (at 1080p)" ./run.sh
```

Press **select** on the remote (Return in the simulator) to open settings: places, playlist and globe speed.

## Test it

```sh
cd GlobeCore && swift test
```

## Layout

| Path | What |
| --- | --- |
| `AsciiTV/` | The tvOS app: Metal renderer, globe screen, settings screen, Apple Music playback. tvOS 17.0+. |
| `GlobeCore/` | Swift package with everything that needs no screen: sun position, land mask, the character grid, label placement, the settings model. Tested on the Mac. |
| branch `prototype/ascii-globe-looks` | Throwaway prototype that compared three looks. "B, Atlas" won and became the app. Kept off main on purpose. |

## How it stays cheap on a 4K screen

- The globe is a 320x90 grid of characters. Which latitude and longitude each character shows is worked out
  once; turning the globe is then an integer offset into the land mask and a cosine-table lookup per cell.
- There is no display link. The app sleeps until the globe has turned half a degree, then draws exactly one
  frame: 6 frames a second at the default speed, one frame every 5 seconds at one turn an hour.
- A frame is one full-screen triangle with no blending or filtering: at most three texture reads per pixel.

## Coastlines

The land mask is baked from Natural Earth 1:50m land (public domain, naturalearthdata.com). To regenerate it,
download `ne_50m_land.geojson` and run `python3 Scripts/bake_landmask.py path/to/ne_50m_land.geojson`.
Lakes are not cut out, so the Great Lakes are drawn as land.

## Before it can ship

- **Music on a real Apple TV.** The simulator has no Apple Music, so it lists sample playlists and plays
  nothing. Real playback needs a device, an Apple Music subscription, and the MusicKit app service enabled
  for the bundle ID in the Apple developer portal. That path compiles but has never been run.
- **Bundle ID.** `com.example.AsciiTV` is a placeholder.
- **App icon and Top Shelf image.** Required for the App Store; not added yet.
