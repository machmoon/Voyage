import MetalKit
import SwiftUI

/// Metal-backed passenger-window renderer. It renders the bundled airport world
/// contract rather than asking a network map SDK for a camera-height scene.
struct AirportWorldMetalView: UIViewRepresentable {
    let frame: AirportWorldFrame
    let isNight: Bool
    let reduceMotion: Bool

    func makeCoordinator() -> Renderer { Renderer() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.clearColor = MTLClearColorMake(0.05, 0.08, 0.12, 1)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = reduceMotion ? 12 : 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        context.coordinator.configure(view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        view.preferredFramesPerSecond = reduceMotion ? 12 : 60
        context.coordinator.frame = frame
        context.coordinator.isNight = isNight
        context.coordinator.reduceMotion = reduceMotion
    }

    final class Renderer: NSObject, MTKViewDelegate {
        var frame = AirportWorldFrame(
            airportCode: "SFO", profile: .sfoBay, aircraft: .voyageClassic,
            side: .left, rollProgress: 0, climbProgress: 0,
            pitchDegrees: 0, bankDegrees: 0, cloudAmount: 0.2,
            visibility: 1, wetRunway: false, elapsed: 0,
            camera: AirportWorldCameraPose(
                position: SIMD3(-2.25, 2.2, 180), yawDegrees: 8,
                pitchDegrees: 0, rollDegrees: 0, fieldOfViewDegrees: 66
            )
        )
        var isNight = false
        var reduceMotion = false
        private var commandQueue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?

        func configure(_ view: MTKView) {
            guard let device = view.device,
                  let library = device.makeDefaultLibrary(),
                  let vertex = library.makeFunction(name: "airport_world_vertex"),
                  let fragment = library.makeFunction(name: "airport_world_fragment") else { return }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
            commandQueue = device.makeCommandQueue()
            view.delegate = self
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let pipeline, let queue = commandQueue, let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable, let encoderCommand = queue.makeCommandBuffer(),
                  let encoder = encoderCommand.makeRenderCommandEncoder(descriptor: descriptor) else { return }
            var uniforms = AirportWorldUniforms(
                viewport: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                elapsed: Float(reduceMotion ? 0 : frame.elapsed),
                roll: Float(frame.rollProgress),
                climb: Float(frame.climbProgress),
                pitch: Float(frame.pitchDegrees / 12),
                bank: Float(frame.bankDegrees / 5),
                clouds: Float(frame.cloudAmount),
                visibility: Float(frame.visibility),
                airport: airportValue(frame.airportCode),
                profile: frame.profile == .sfoCity ? 1 : 0,
                leftSide: frame.side == .left ? 1 : 0,
                wet: frame.wetRunway ? 1 : 0,
                night: isNight ? 1 : 0
            )
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<AirportWorldUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            encoderCommand.present(drawable)
            encoderCommand.commit()
        }

        private func airportValue(_ code: String) -> Float {
            Airport.all.firstIndex(where: { $0.code == code }).map { Float($0) } ?? 0
        }
    }
}

private struct AirportWorldUniforms {
    var viewport: SIMD2<Float>
    var elapsed: Float
    var roll: Float
    var climb: Float
    var pitch: Float
    var bank: Float
    var clouds: Float
    var visibility: Float
    var airport: Float
    var profile: Float
    var leftSide: Float
    var wet: Float
    var night: Float
}
