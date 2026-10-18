import CoreVideo
import Testing
@testable import AutoSwitchCore

struct FrameStoreTests {
    let a = CameraID("A")
    let b = CameraID("B")

    func makeFrame() throws -> CVReadOnlyPixelBuffer {
        CVReadOnlyPixelBuffer(try CVMutablePixelBuffer(CVPixelBufferCreationAttributes(
            pixelFormatType: CVPixelFormatType(rawValue: VirtualCamera.pixelFormat),
            size: CVImageSize(width: 16, height: 16)
        )))
    }

    /// Ends the stream by starting a new one, then returns every frame it passed on.
    func collect(_ frames: AsyncStream<LiveFrame>, from store: FrameStore) async -> [LiveFrame] {
        _ = store.makeLiveFrames()
        var collected: [LiveFrame] = []
        for await frame in frames {
            collected.append(frame)
        }
        return collected
    }

    @Test func passesOnTheLiveCamerasFrames() async throws {
        let store = FrameStore()
        let frames = store.makeLiveFrames()
        store.setLiveCamera(a)
        let frame = try makeFrame()
        store.store(frame, for: a)

        let collected = await collect(frames, from: store)
        #expect(collected.map(\.camera) == [a])
        #expect(collected.first?.frame === frame)
    }

    @Test func ignoresOtherCameras() async throws {
        let store = FrameStore()
        let frames = store.makeLiveFrames()
        store.setLiveCamera(a)
        store.store(try makeFrame(), for: b)

        #expect(await collect(frames, from: store).isEmpty)
    }

    @Test func passesOnNothingWithoutALiveCamera() async throws {
        let store = FrameStore()
        let frames = store.makeLiveFrames()
        store.store(try makeFrame(), for: a)

        #expect(await collect(frames, from: store).isEmpty)
    }

    @Test func switchingPassesOnTheNewCamerasLatestFrame() async throws {
        let store = FrameStore()
        let frames = store.makeLiveFrames()
        let frame = try makeFrame()
        store.store(frame, for: b)
        store.setLiveCamera(b)

        let collected = await collect(frames, from: store)
        #expect(collected.map(\.camera) == [b])
        #expect(collected.first?.frame === frame)
    }

    @Test func keepsOnlyTheNewestFrame() async throws {
        let store = FrameStore()
        let frames = store.makeLiveFrames()
        store.setLiveCamera(a)
        let newest = try makeFrame()
        store.store(try makeFrame(), for: a)
        store.store(newest, for: a)

        let collected = await collect(frames, from: store)
        #expect(collected.count == 1)
        #expect(collected.first?.frame === newest)
    }

    @Test func aNewStreamGetsTheFramesInstead() async throws {
        let store = FrameStore()
        let old = store.makeLiveFrames()
        let new = store.makeLiveFrames()
        store.setLiveCamera(a)
        store.store(try makeFrame(), for: a)

        // The old stream has ended, so it finishes without frames.
        var oldFrames = 0
        for await _ in old {
            oldFrames += 1
        }
        #expect(oldFrames == 0)
        #expect(await collect(new, from: store).count == 1)
    }
}
