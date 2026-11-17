# Spec: smoother globe, real city lights, better place entry, working Apple Music

Status: agreed in a design interview, not yet built. Vocabulary is in [GLOSSARY.md](../GLOSSARY.md).

Four changes were asked for. This file records what was decided and breaks the work into steps.

## Decisions

### 1. Place entry
Typing signed decimals on the remote keyboard is the problem.

- **Primary path: pick a City.** Search as you type, using the letters-only tvOS keyboard. Before you type, the list shows the largest cities. Results are biggest first. The picker searches all ~7,000 Natural Earth populated places.
- **Fallback: Custom coordinates.** Digit wheels: N/S and E/W toggles, and one column per digit, 2 decimals (about 1 km). Swipe up/down to change a digit and left/right to move between digits. No minus sign or decimal point is ever typed.
- A **Place** is always stored as label plus coordinates, never as a reference to a City. Changing the city data later cannot move or break a saved Place. Saved Places from older versions load unchanged.
- Choosing a City pre-fills the label with its name; the label stays editable.

### 2. Smooth animation (about 60 fps)
- Characters glide with the ground by sub-cell pixel offsets: land, ice, city lights and **Labels** all move continuously. The retro text look stays.
- **Adaptive:** redraw at the display's refresh rate (up to 60) only while something moves at least about 1 px per frame. Slow down or sleep when the globe is nearly still (for example the one-turn-an-hour speed). This reverses the README's "no display link" design. Record it as ADR 0001 once the prototype settles the edge treatment.
- **Prototype first**, throwaway and kept off main. It answers one question: how should characters behave near the edge of the disc, where the surface squashes? Either thin the characters out toward the edge, or shrink and stretch them with the sphere. The user picks from screenshots or a clip.
- Labels glide with the ground. The collision rules still choose which labels show, but run less often and fade, so labels do not flicker.
- **Target hardware:** the "Living Room" Apple TV 4K (1st generation, A10X) at 4K. Measure there, not only in the simulator. If 60 fps is not held, rework the renderer first. Only after that fails, ask the user to choose between 30 fps and 1080p.

### 3. City lights
- Source: Natural Earth populated places (public domain), baked by a script in the same way as `Scripts/bake_landmask.py`.
- About 1,500 of the biggest cities are drawn as City lights, in three size tiers by population (for example `.`, `+`, `*`), with brightness following the tier.
- All latitudes, not only 60°S to 60°N. Steady, no twinkling. Amber, as now. Each light stays fixed to the ground.
- This replaces the 900 random points in `GlobeGrid.placeCityLights`.

### 4. Apple Music
- Library playlists only (the current behaviour), looped. No catalogue search.
- **Play order is a setting:** in order (default) or shuffled. Settings saved by older versions decode to the default.
- Music **and rotation** pause when the app leaves the foreground or when settings opens. They resume on return, and a changed playlist starts at that point, not when it is picked.
- Failures (subscription lapsed, playlist deleted, no network) show as a short amber message on the globe screen that fades after about 12 seconds, like the existing hint.
- The simulator keeps its sample playlists and plays nothing.
- Bundle ID: `com.joshaustin.AsciiTV`. Replaces the placeholder `com.example.AsciiTV` everywhere, including `run.sh`.

## Work breakdown

Each step ends in something that builds, and the tests in `GlobeCore` pass. Steps 1, 2 and 4 are independent of each other. Step 5 needs 4. Step 6 needs 5. Step 8 needs 7.

1. **Apple Music setup, then playback on the real device** *(partly the user's)*
   - User: register the App ID `com.joshaustin.AsciiTV` in the Apple Developer portal with the MusicKit app service enabled.
   - Set the bundle ID and `DEVELOPMENT_TEAM` in the project and in `run.sh`.
   - Run on the "Living Room" Apple TV and fix what fails.
   - Done when a library playlist loops on that Apple TV.
2. **Music behaviour changes.**
   - Shuffle setting (default in order) in `GlobeSettings` and the settings screen.
   - Pause music and rotation on leaving the foreground or opening settings; resume, and start a changed playlist, on return.
   - Failure message on the globe screen.
   - Done when the behaviours above hold on the device.
3. **City data bake.**
   - Script that bakes Natural Earth populated places (name, country, latitude, longitude, population) into a data file in `GlobeCore`, with a tier for each of the top ~1,500.
   - Tests for lookup and search.
   - Done when search for "São Paulo" or "sao paulo" finds the city and the biggest cities sort first.
4. **City lights from real data.**
   - Replace the random lights with the baked cities in three tiers, at all latitudes.
   - Done when major cities (Tokyo, Cairo, Lagos, New York) are lit on the night side and the oceans are dark.
5. **Place entry.**
   - City search picker and digit-wheel Custom coordinates, replacing the text fields in `PlaceEditor`.
   - Tests for the wheel-to-coordinate conversion and for search.
   - Done when a Place can be added on the remote with no number typing.
6. **Glide prototype** *(throwaway, own branch)*.
   - Prototype both edge treatments at 4K; capture screenshots or a clip.
   - Done when the user has chosen one.
7. **ADR 0001 and the glide renderer.**
   - Write the ADR (adaptive display-link renderer replaces the event-driven one; why; the power trade-off).
   - Build the chosen look into `Renderer`, `Shaders.metal` and `GlobeGrid`, with adaptive frame pacing.
   - Done when the globe glides at the default speed in the simulator and sleeps at the slowest.
8. **Labels glide, then measure on the A10X.**
   - Labels follow their Place exactly; collision choices throttled and faded.
   - Measure frame pacing at 4K on the "Living Room" Apple TV at each speed.
   - Done when 60 fps holds at the default speed, or the fallback question has been put to the user.
9. **Docs.**
   - Update the README (renderer, city lights, settings, Music setup, bundle ID, "Before it can ship") and keep GLOSSARY.md current.

## Out of scope
- Apple Music catalogue search or playlists you haven't added to your library.
- Browsing cities by country.
- Twinkling lights or population-density / satellite night-light imagery.
- App icon, Top Shelf image and App Store submission (already listed in the README).
