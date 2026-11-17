import XCTest
@testable import GlobeCore

private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

final class SolarPositionTests: XCTestCase {
    func testSunIsOverTheEquatorAtTheMarchEquinox() {
        XCTAssertEqual(SolarPosition.subsolarPoint(at: utc(2024, 3, 20, 3, 6)).lat, 0, accuracy: 0.05)
    }

    func testSunReachesTheTropicsAtTheSolstices() {
        XCTAssertEqual(SolarPosition.subsolarPoint(at: utc(2024, 6, 20, 20, 51)).lat, 23.44, accuracy: 0.05)
        XCTAssertEqual(SolarPosition.subsolarPoint(at: utc(2024, 12, 21, 9, 21)).lat, -23.44, accuracy: 0.05)
    }

    func testSunIsOverGreenwichAtNoonUTCWhenTheEquationOfTimeIsZero() {
        // Around 15 April and 1 September clock noon and solar noon coincide.
        XCTAssertEqual(SolarPosition.subsolarPoint(at: utc(2025, 4, 15, 12)).lon, 0, accuracy: 0.3)
        XCTAssertEqual(SolarPosition.subsolarPoint(at: utc(2025, 9, 1, 12)).lon, 0, accuracy: 0.3)
    }

    func testSunRunsAheadOfTheClockInEarlyNovember() {
        // Equation of time is about +16.4 minutes on 3 November: the sun is already 4.1 degrees west at noon.
        XCTAssertEqual(SolarPosition.subsolarPoint(at: utc(2025, 11, 3, 12)).lon, -4.1, accuracy: 0.2)
    }

    func testSunMovesWestFifteenDegreesAnHour() {
        let a = SolarPosition.subsolarPoint(at: utc(2025, 4, 15, 12)).lon
        let b = SolarPosition.subsolarPoint(at: utc(2025, 4, 15, 13)).lon
        XCTAssertEqual(a - b, 15, accuracy: 0.05)
    }

    func testDaylightFollowsTheSun() {
        let sun = SubsolarPoint(lat: 0, lon: 0)
        XCTAssertTrue(SolarPosition.isDaylight(lat: 10, lon: 20, sun: sun))
        XCTAssertFalse(SolarPosition.isDaylight(lat: 10, lon: 170, sun: sun))
        // Midnight sun: with the sun at 23N the north pole is lit and the south pole is not.
        XCTAssertTrue(SolarPosition.isDaylight(lat: 89, lon: 180, sun: SubsolarPoint(lat: 23, lon: 0)))
        XCTAssertFalse(SolarPosition.isDaylight(lat: -89, lon: 0, sun: SubsolarPoint(lat: 23, lon: 0)))
    }
}

final class LandMaskTests: XCTestCase {
    func testContinentsAndOceansAreWhereYouExpect() {
        let m = LandMask.naturalEarth
        for (name, lat, lon) in [("Sahara", 22.0, 10.0), ("Kansas", 38.0, -98.0), ("Siberia", 62.0, 100.0),
                                 ("Amazon", -5.0, -60.0), ("Outback", -25.0, 134.0), ("Antarctica", -85.0, 0.0),
                                 ("England", 52.5, -1.5), ("Honshu", 36.0, 138.5), ("Madagascar", -19.0, 47.0),
                                 ("New Zealand", -44.0, 170.5), ("Iceland", 65.0, -18.0), ("Florida", 28.0, -81.5)] {
            XCTAssertTrue(m.isLand(lat: lat, lon: lon), name)
        }
        for (name, lat, lon) in [("mid Pacific", 0.0, -150.0), ("mid Atlantic", 30.0, -40.0),
                                 ("Indian Ocean", -30.0, 80.0), ("Arctic Ocean", 88.0, 0.0),
                                 ("Mediterranean", 35.0, 18.0), ("Gulf of Mexico", 25.0, -90.0),
                                 ("Hudson Bay", 60.0, -85.0), ("Caspian Sea", 42.0, 51.0), ("North Sea", 56.0, 3.0)] {
            XCTAssertFalse(m.isLand(lat: lat, lon: lon), name)
        }
    }
}

final class GlobeClockTests: XCTestCase {
    func testOneFullTurnPerPeriod() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let c0 = GlobeClock.centreColumn(at: t0, period: 120)
        XCTAssertEqual(GlobeClock.centreColumn(at: t0.addingTimeInterval(120), period: 120), c0)
        XCTAssertNotEqual(GlobeClock.centreColumn(at: t0.addingTimeInterval(60), period: 120), c0)
    }

    func testSurfaceTravelsWestToEast() {
        // The meridian facing the viewer moves west, which is what makes the ground appear to move east.
        let t0 = Date(timeIntervalSince1970: 1_800_000_010)
        let a = GlobeClock.centreColumn(at: t0, period: 120)
        let b = GlobeClock.centreColumn(at: t0.addingTimeInterval(1), period: 120)
        XCTAssertEqual((a - b + LandMask.cols) % LandMask.cols, 6)   // 3 degrees a second = 6 columns
    }

    func testNextChangeIsTheNextColumnBoundary() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000.05)
        let next = GlobeClock.nextChange(after: t0, period: 120)
        XCTAssertGreaterThan(next, t0)
        XCTAssertLessThanOrEqual(next.timeIntervalSince(t0), 120.0 / 720 + 1e-6)
        let before = GlobeClock.centreColumn(at: next.addingTimeInterval(-0.001), period: 120)
        let after = GlobeClock.centreColumn(at: next.addingTimeInterval(0.001), period: 120)
        XCTAssertEqual(before, GlobeClock.centreColumn(at: t0, period: 120))
        XCTAssertNotEqual(before, after)
    }

    func testColumnsMapToLongitudes() {
        XCTAssertEqual(GlobeClock.longitude(ofColumn: 0), -180)
        XCTAssertEqual(GlobeClock.longitude(ofColumn: 360), 0)
    }
}

final class GlobeLayoutTests: XCTestCase {
    let layout = GlobeLayout.centred(widthPx: 3840, heightPx: 2160)

    func testThePointTheCameraLooksAtIsInTheMiddle() throws {
        let p = try XCTUnwrap(layout.project(lat: layout.tiltDeg, lon: 30, centreLonDeg: 30))
        XCTAssertEqual(p.x, 1920, accuracy: 0.001)
        XCTAssertEqual(p.y, 1080, accuracy: 0.001)
    }

    func testEastIsRightAndNorthIsUp() throws {
        let centre = try XCTUnwrap(layout.project(lat: 18, lon: 0, centreLonDeg: 0))
        let east = try XCTUnwrap(layout.project(lat: 18, lon: 30, centreLonDeg: 0))
        let north = try XCTUnwrap(layout.project(lat: 48, lon: 0, centreLonDeg: 0))
        XCTAssertGreaterThan(east.x, centre.x)
        XCTAssertLessThan(north.y, centre.y)
    }

    func testTheFarSideIsHidden() {
        XCTAssertNil(layout.project(lat: 0, lon: 180, centreLonDeg: 0))
        XCTAssertNil(layout.project(lat: -80, lon: 0, centreLonDeg: 0))   // tilted away from the south pole
    }
}

final class GlobeGridTests: XCTestCase {
    let layout = GlobeLayout.centred(widthPx: 3840, heightPx: 2160)
    lazy var grid = GlobeGrid(layout: layout, cellW: 12, cellH: 24)

    private func column(forLon lon: Double) -> Int { Int((lon + 180) * 2) }
    private var centre: GlobeCell { grid.cell(col: grid.cols / 2, row: grid.rows / 2) }

    func testA4KScreenIs320By90Characters() {
        XCTAssertEqual(grid.cols, 320)
        XCTAssertEqual(grid.rows, 90)
        XCTAssertEqual(grid.cells.count, 320 * 90 * 4)
    }

    func testDaylitLandAndOceanUseTheirOwnInks() {
        grid.update(centreColumn: column(forLon: 10), sun: SubsolarPoint(lat: 18, lon: 10))    // Sahara at noon
        XCTAssertTrue([Ink.land, .desert].contains(centre.ink))
        XCTAssertGreaterThan(centre.brightness, 0.8)

        grid.update(centreColumn: column(forLon: -150), sun: SubsolarPoint(lat: 18, lon: -150)) // Pacific at noon
        XCTAssertEqual(centre.ink, .ocean)
        XCTAssertTrue("~-".contains(centre.glyph))
    }

    func testTheNightSideIsDarkWithCityLights() {
        grid.update(centreColumn: column(forLon: 10), sun: SubsolarPoint(lat: 0, lon: -170))    // Sahara at midnight
        XCTAssertTrue(".*".contains(centre.glyph))

        var lights = 0, dayGlyphs = 0
        for r in 30..<60 { for c in 130..<190 {
            let cell = grid.cell(col: c, row: r)
            if cell.glyph == "*" && cell.ink == .amber { lights += 1 }
            if cell.ink == .land || cell.ink == .desert { dayGlyphs += 1 }
        } }
        XCTAssertGreaterThan(lights, 20)
        XCTAssertEqual(dayGlyphs, 0)
    }

    func testCityLightsGlideInsteadOfFlickering() {
        // Night over Africa and Europe. Step the rotation one column at a time: every light near the middle of
        // the disc must have been in the same cell or the one beside it on the previous step.
        let sun = SubsolarPoint(lat: 0, lon: -170)
        func lights(_ centre: Int) -> Set<[Int]> {
            grid.update(centreColumn: centre, sun: sun)
            var out = Set<[Int]>()
            for r in 15..<75 { for c in 110..<210 where grid.cell(col: c, row: r).glyph == "*" { out.insert([c, r]) } }
            return out
        }
        var previous = lights(column(forLon: 10))
        var seen = 0
        for step in 1...40 {
            let now = lights(column(forLon: 10) - step)
            for cell in now where cell[0] > 112 && cell[0] < 207 && cell[1] > 16 && cell[1] < 73 {
                seen += 1
                let cameFrom = (-1...1).flatMap { dc in (-1...1).map { dr in [cell[0] + dc, cell[1] + dr] } }
                XCTAssertTrue(cameFrom.contains { previous.contains($0) }, "light appeared from nowhere at \(cell)")
            }
            previous = now
        }
        XCTAssertGreaterThan(seen, 500)
    }

    func testOnlyCityLightsBreakUpTheNightSide() {
        grid.update(centreColumn: column(forLon: 10), sun: SubsolarPoint(lat: 0, lon: -170))
        for r in 20..<70 { for c in 120..<200 {
            XCTAssertTrue(" .*".contains(grid.cell(col: c, row: r).glyph))
        } }
    }

    func testTheTerminatorIsATwilightBand() {
        grid.update(centreColumn: column(forLon: 10), sun: SubsolarPoint(lat: 0, lon: 100))     // sun 90 degrees east
        XCTAssertEqual(centre.ink, .twilight)
    }

    func testTheBackdropDoesNotChangeWhenTheGlobeTurns() {
        grid.update(centreColumn: 0, sun: SubsolarPoint(lat: 0, lon: 0))
        let corner = grid.cell(col: 0, row: 0), before = grid.cells
        grid.update(centreColumn: 300, sun: SubsolarPoint(lat: 0, lon: 0))
        XCTAssertEqual(grid.cell(col: 0, row: 0), corner)
        XCTAssertNotEqual(grid.cells, before)
    }
}

final class LabelLayoutTests: XCTestCase {
    private func cellsCovered(_ placed: [PlacedText], cols: Int) -> [Int] {
        placed.flatMap { p in (0..<p.text.count).map { p.row * cols + p.col + $0 } }
    }

    func testLabelGoesToTheRightOfItsMarker() {
        let placed = LabelLayout.place([LabelMarker(col: 40, row: 10, text: "Tokyo")], cols: 160, rows: 45)
        XCTAssertEqual(placed, [PlacedText(col: 40, row: 10, text: "o"),
                                PlacedText(col: 41, row: 10, text: "--[ Tokyo ]")])
    }

    func testLabelFlipsLeftAtTheRightEdge() {
        let placed = LabelLayout.place([LabelMarker(col: 150, row: 10, text: "Tokyo")], cols: 160, rows: 45)
        XCTAssertEqual(placed.last, PlacedText(col: 150 - 11, row: 10, text: "[ Tokyo ]--"))
    }

    func testNeighbouringLabelsNeverOverlap() {
        let markers = (0..<8).map { LabelMarker(col: 60 + $0 * 2, row: 20 + $0 % 2, text: "Place \($0)") }
        let placed = LabelLayout.place(markers, cols: 160, rows: 45)
        let covered = cellsCovered(placed, cols: 160)
        XCTAssertEqual(covered.count, Set(covered).count)
        XCTAssertEqual(placed.filter { $0.text == "o" }.count, 8)     // every marker is still drawn
        XCTAssertGreaterThan(placed.count, 10)                         // and several labels found room
    }

    func testLabelIsDroppedWhenThereIsNoRoomButTheMarkerStays() {
        let placed = LabelLayout.place([LabelMarker(col: 6, row: 10, text: String(repeating: "x", count: 24))],
                                       cols: 20, rows: 45)
        XCTAssertEqual(placed, [PlacedText(col: 6, row: 10, text: "o")])
    }

    func testLongLabelsAreCut() {
        let placed = LabelLayout.place([LabelMarker(col: 10, row: 10, text: String(repeating: "x", count: 60))],
                                       cols: 160, rows: 45)
        XCTAssertEqual(placed.last?.text.count, 24 + 6)
    }

    func testTextStaysOutOfTheOverscanMargin() {
        let placed = LabelLayout.place([LabelMarker(col: 80, row: 2, text: "Top"), LabelMarker(col: 8, row: 20, text: "Left")],
                                       cols: 160, rows: 45)
        for p in placed where p.text != "o" {
            XCTAssertGreaterThanOrEqual(p.col, 5)
            XCTAssertGreaterThanOrEqual(p.row, 2)
        }
    }
}

final class GlobeSettingsTests: XCTestCase {
    func testSettingsSurviveARoundTrip() {
        let s = GlobeSettings(points: [GeoPoint(label: "Tokyo", lat: 35.68, lon: 139.69)],
                              playlistID: "p.abc", playlistName: "Orbital Jazz", rotationPeriod: 600)
        XCTAssertEqual(GlobeSettings(json: s.json), s)
    }

    func testOlderSettingsWithMissingFieldsStillLoad() {
        let s = GlobeSettings(json: #"{"points":[]}"#)
        XCTAssertEqual(s, GlobeSettings())
        XCTAssertEqual(s?.rotationPeriod, 120)
    }

    func testAnUnknownRotationSpeedFallsBackToTheDefault() {
        XCTAssertEqual(GlobeSettings(json: #"{"rotationPeriod":7}"#)?.rotationPeriod, 120)
    }

    func testGarbageIsRejected() {
        XCTAssertNil(GlobeSettings(json: "not json"))
    }

    func testCoordinatesAreClampedToTheGlobe() {
        let p = GeoPoint(label: "x", lat: 123, lon: -500)
        XCTAssertEqual(p.lat, 90)
        XCTAssertEqual(p.lon, -180)
    }

    func testLabelsAreFoldedToASCII() {
        XCTAssertEqual("São Paulo".asciiFolded, "Sao Paulo")
        XCTAssertEqual("Zürich".asciiFolded, "Zurich")
        XCTAssertFalse("東京".asciiFolded.contains("?"))
    }
}

final class TextGridTests: XCTestCase {
    func testTextIsClippedAtTheEdges() {
        let g = TextGrid(cols: 8, rows: 2)
        g.put("abcdef", col: 5, row: 0, ink: .amber)
        g.put("zz", col: 0, row: 9, ink: .amber)
        XCTAssertEqual(g.text(row: 0), "     abc")
        g.clear()
        XCTAssertEqual(g.text(row: 0), "        ")
    }
}
