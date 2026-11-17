import Combine
import GlobeCore
import MetalKit
import SwiftUI

/// The globe screen. Press select on the remote to open settings.
///
/// Power: there is no display link. The view sleeps until the globe has turned by one land-mask column
/// (half a degree), then rebuilds the character grid and presents exactly one frame. At the default speed
/// that is 6 frames a second; at one turn an hour it is one frame every 5 seconds.
final class GlobeViewController: UIViewController, MTKViewDelegate {
    /// Character cells in points. On a 4K screen (2x) the globe is 320x90 characters of 12x24 pixels.
    private static let globeCellPt = (w: 6, h: 12)
    /// Labels use bigger characters so they can be read from across the room.
    private static let labelCellPt = (w: 12, h: 24)
    private static let hintDuration: TimeInterval = 12

    private let store: SettingsStore
    private let music: MusicController
    private var subscriptions = Set<AnyCancellable>()

    private let metalView = MTKView()
    private var renderer: Renderer?
    private var layout: GlobeLayout?
    private var globe: GlobeGrid?
    private var labels: TextGrid?
    private var labelCellPx = (w: 1, h: 1)
    private var builtForSize = CGSize.zero

    private var timer: Timer?
    private var running = false
    private var showHint = true

    init(store: SettingsStore, music: MusicController) {
        self.store = store
        self.music = music
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        metalView.frame = view.bounds
        metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        metalView.device = MTLCreateSystemDefaultDevice()
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = true
        metalView.isPaused = true                 // we call draw() ourselves, only when something changed
        metalView.enableSetNeedsDisplay = false
        metalView.delegate = self
        view.addSubview(metalView)
        renderer = Renderer(view: metalView)

        store.$settings
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(start), name: UIScene.didActivateNotification, object: nil)
        center.addObserver(self, selector: #selector(stop), name: UIScene.willDeactivateNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        start()
        if showHint {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hintDuration) { [weak self] in
                self?.showHint = false
                self?.refresh()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        rebuildIfNeeded()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { rebuildIfNeeded() }
    func draw(in view: MTKView) { renderer?.draw(in: view) }

    // MARK: Drawing

    private func rebuildIfNeeded() {
        let size = metalView.drawableSize
        guard size.width > 0, view.bounds.width > 0, size != builtForSize else { return }
        builtForSize = size
        let scale = max(1, Int((size.width / view.bounds.width).rounded()))
        let globeCell = (w: Self.globeCellPt.w * scale, h: Self.globeCellPt.h * scale)
        labelCellPx = (w: Self.labelCellPt.w * scale, h: Self.labelCellPt.h * scale)

        let layout = GlobeLayout.centred(widthPx: Int(size.width), heightPx: Int(size.height))
        let globe = GlobeGrid(layout: layout, cellW: globeCell.w, cellH: globeCell.h)
        let labels = TextGrid(cols: (layout.widthPx + labelCellPx.w - 1) / labelCellPx.w,
                              rows: (layout.heightPx + labelCellPx.h - 1) / labelCellPx.h)
        renderer?.configure(globe: globe, globeCell: globeCell, labels: labels, labelCell: labelCellPx)
        self.layout = layout
        self.globe = globe
        self.labels = labels
        refresh()
    }

    /// Draws one frame for the current instant and schedules the next.
    private func refresh() {
        timer?.invalidate()
        guard running, let layout, let globe, let labels else { return }
        let now = Date()
        let period = store.settings.rotationPeriod
        let column = GlobeClock.centreColumn(at: now, period: period)
        let centreLon = GlobeClock.longitude(ofColumn: column)

        globe.update(centreColumn: column, sun: SolarPosition.subsolarPoint(at: now))

        labels.clear()
        let markers = store.settings.points.compactMap { point -> LabelMarker? in
            guard let p = layout.project(lat: point.lat, lon: point.lon, centreLonDeg: centreLon) else { return nil }
            return LabelMarker(col: Int(p.x) / labelCellPx.w, row: Int(p.y) / labelCellPx.h, text: point.label.asciiFolded)
        }
        for text in LabelLayout.place(markers, cols: labels.cols, rows: labels.rows) {
            labels.put(text.text, col: text.col, row: text.row, ink: .amber)
        }
        if showHint {
            let hint = "[ PRESS SELECT FOR SETTINGS ]"
            labels.put(hint, col: (labels.cols - hint.count) / 2, row: labels.rows - 3, ink: .white, brightness: 0.7)
        }

        renderer?.upload(globe: globe, labels: labels)
        metalView.draw()

        let next = Timer(fire: GlobeClock.nextChange(after: now, period: period), interval: 0, repeats: false) { [weak self] _ in
            self?.refresh()
        }
        next.tolerance = period / Double(LandMask.cols) / 5
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    @objc private func start() {
        guard !running, viewIfLoaded?.window != nil else { return }
        running = true
        refresh()
        Task { await music.resume() }
    }

    @objc private func stop() {
        running = false
        timer?.invalidate()
    }

    // MARK: Remote

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard presses.contains(where: { $0.type == .select }) else {
            super.pressesBegan(presses, with: event)
            return
        }
        showHint = false
        present(UIHostingController(rootView: SettingsView(store: store, music: music)), animated: true)
    }
}
