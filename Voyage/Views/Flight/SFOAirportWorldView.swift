import RealityKit
import SwiftUI
import UIKit

/// Offline, non-AR RealityKit world for SFO runway 28 departures. Geometry is
/// deliberately compact; the session-owned `AirportWorldFrame` moves only the
/// passenger camera and weather treatment.
struct SFOAirportWorldView: UIViewRepresentable {
    let frame: AirportWorldFrame
    let isNight: Bool
    let condition: SkyCondition

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        // These cinematic post effects cost GPU time but add little inside the
        // small aircraft window. Disabling them noticeably steadies older
        // devices and the simulator without flattening the authored lighting.
        view.renderOptions.insert([
            .disableCameraGrain,
            .disableDepthOfField,
            .disableMotionBlur,
            .disableHDR,
        ])
        context.coordinator.buildScene(in: view)
        context.coordinator.update(frame: frame, isNight: isNight, condition: condition, in: view)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.update(frame: frame, isNight: isNight, condition: condition, in: view)
    }

    final class Coordinator {
        private let root = AnchorEntity(world: .zero)
        private let camera = PerspectiveCamera()
        private let cloudRoot = Entity()
        private var runway: ModelEntity?
        private var water: ModelEntity?
        private var ground: ModelEntity?
        private var skyline: [ModelEntity] = []
        private var airportBuildings: [ModelEntity] = []
        private var clouds: [ModelEntity] = []
        private var didBuild = false
        private var hasCameraPose = false
        private var lastSurfaceAppearance: SurfaceAppearance?
        private var lastCloudAppearance: CloudAppearance?

        private struct SurfaceAppearance: Equatable {
            let isNight: Bool
            let wetRunway: Bool
            let visibilityBucket: Int
        }

        private struct CloudAppearance: Equatable {
            let isNight: Bool
            let alphaBucket: Int
        }

        func buildScene(in view: ARView) {
            guard !didBuild else { return }
            didBuild = true
            view.scene.addAnchor(root)

            camera.camera.fieldOfViewInDegrees = 66
            root.addChild(camera)
            addSun()
            addGroundAndBay()
            addRunway()
            addAirportBuildings()
            addTerrainAndSkyline()
            addCloudDeck()
        }

        func update(frame: AirportWorldFrame, isNight: Bool, condition: SkyCondition, in view: ARView) {
            let pose = frame.camera
            camera.camera.fieldOfViewInDegrees = Float(pose.fieldOfViewDegrees)

            let yaw = simd_quatf(angle: radians(pose.yawDegrees), axis: SIMD3(0, 1, 0))
            let pitch = simd_quatf(angle: radians(pose.pitchDegrees), axis: SIMD3(1, 0, 0))
            let roll = simd_quatf(angle: radians(pose.rollDegrees), axis: SIMD3(0, 0, 1))
            let cameraTarget = Transform(
                scale: .one,
                rotation: yaw * pitch * roll,
                translation: SIMD3(Float(pose.position.x), Float(pose.position.y), Float(pose.position.z))
            )
            if hasCameraPose {
                camera.move(to: cameraTarget, relativeTo: root, duration: 0.27, timingFunction: .linear)
            } else {
                camera.transform = cameraTarget
                hasCameraPose = true
            }

            // Weather and time of day are stable for a flight. Avoid rebuilding
            // dozens of material arrays for every 250 ms position snapshot.
            let surfaceAppearance = SurfaceAppearance(
                isNight: isNight,
                wetRunway: frame.wetRunway,
                visibilityBucket: Int((frame.visibility * 20).rounded())
            )
            if surfaceAppearance != lastSurfaceAppearance {
                let sky = isNight
                    ? UIColor(red: 0.018, green: 0.028, blue: 0.075, alpha: 1)
                    : UIColor(red: 0.30, green: 0.58, blue: 0.78, alpha: 1)
                view.environment.background = .color(sky.withAlphaComponent(CGFloat(frame.visibility)))
                runway?.model?.materials = [runwayMaterial(wet: frame.wetRunway, night: isNight)]
                water?.model?.materials = [waterMaterial(night: isNight)]
                ground?.model?.materials = [groundMaterial(night: isNight)]
                updateBuildings(isNight: isNight)
                lastSurfaceAppearance = surfaceAppearance
            }

            // Preserve a clear landmark reveal after rotation, then enter the
            // cloud deck during the latter half of the compressed climb.
            let cloudPresence = min(1, max(0, (frame.climbProgress - 0.42) / 0.34))
            cloudRoot.isEnabled = frame.cloudAmount > 0.12 && cloudPresence > 0
            let cloudAlpha = CGFloat(min(0.46, frame.cloudAmount * cloudPresence * 0.72))
            let cloudAppearance = CloudAppearance(isNight: isNight, alphaBucket: Int((cloudAlpha * 20).rounded()))
            if cloudAppearance != lastCloudAppearance {
                let cloudColor = (isNight ? UIColor(red: 0.32, green: 0.37, blue: 0.48, alpha: cloudAlpha)
                                          : UIColor.white.withAlphaComponent(cloudAlpha))
                let cloudMaterial = SimpleMaterial(color: cloudColor, roughness: 1, isMetallic: false)
                clouds.forEach { $0.model?.materials = [cloudMaterial] }
                lastCloudAppearance = cloudAppearance
            }
            let cloudTarget = Transform(
                scale: cloudRoot.scale,
                rotation: cloudRoot.orientation,
                translation: SIMD3(
                    cloudRoot.position.x,
                    cloudRoot.position.y,
                    Float(pose.position.z - 1_450
                          + (frame.elapsed * 8).truncatingRemainder(dividingBy: 180))
                )
            )
            cloudRoot.move(to: cloudTarget, relativeTo: root, duration: 0.27, timingFunction: .linear)
        }

        private func addSun() {
            let sun = DirectionalLight()
            sun.light.intensity = 16_000
            sun.orientation = simd_quatf(angle: -.pi / 3, axis: SIMD3(1, 0, 0))
            root.addChild(sun)
        }

        private func addGroundAndBay() {
            let bay = ModelEntity(
                mesh: .generatePlane(width: 18_000, depth: 15_000),
                materials: [waterMaterial(night: false)]
            )
            bay.position = SIMD3(0, -1.2, -4_000)
            root.addChild(bay)
            water = bay

            let peninsula = ModelEntity(
                mesh: .generateBox(width: 2_700, height: 1.0, depth: 8_000),
                materials: [groundMaterial(night: false)]
            )
            peninsula.position = SIMD3(-1_000, -0.55, -2_200)
            root.addChild(peninsula)
            ground = peninsula
        }

        private func addRunway() {
            let runwayEntity = ModelEntity(
                mesh: .generateBox(width: 62, height: 0.32, depth: 3_650),
                materials: [runwayMaterial(wet: false, night: false)]
            )
            runwayEntity.position = SIMD3(0, 0, -1_620)
            root.addChild(runwayEntity)
            runway = runwayEntity

            let white = SimpleMaterial(color: .white, roughness: 0.72, isMetallic: false)
            for z in stride(from: 80.0, through: -3_250.0, by: -96.0) {
                let stripe = ModelEntity(
                    mesh: .generateBox(width: 1.2, height: 0.05, depth: 31),
                    materials: [white]
                )
                stripe.position = SIMD3(0, 0.20, Float(z))
                root.addChild(stripe)
            }
            for x in [-29.0, 29.0] {
                let edge = ModelEntity(
                    mesh: .generateBox(width: 0.45, height: 0.05, depth: 3_620),
                    materials: [white]
                )
                edge.position = SIMD3(Float(x), 0.20, -1_620)
                root.addChild(edge)
            }
        }

        private func addAirportBuildings() {
            let terminalCenter = SFOAirportWorldData.localPosition(for: SFOAirportWorldData.terminal)
            for index in 0..<9 {
                let width = Float(80 + (index % 3) * 42)
                let height = Float(22 + (index % 4) * 11)
                let building = ModelEntity(
                    mesh: .generateBox(width: width, height: height, depth: 75),
                    materials: [buildingMaterial(night: false, accent: index.isMultiple(of: 3))]
                )
                building.position = SIMD3(
                    Float(terminalCenter.x) + Float(index - 4) * 105,
                    height / 2,
                    Float(terminalCenter.z) + Float(index % 2) * 90
                )
                root.addChild(building)
                airportBuildings.append(building)
            }
        }

        private func addTerrainAndSkyline() {
            let mountainPosition = SFOAirportWorldData.localPosition(
                for: SFOAirportWorldData.sanBrunoMountain,
                elevation: 210
            )
            let mountain = ModelEntity(
                mesh: .generateSphere(radius: 440),
                materials: [SimpleMaterial(color: UIColor(red: 0.16, green: 0.25, blue: 0.18, alpha: 1), roughness: 1, isMetallic: false)]
            )
            mountain.scale = SIMD3(1.35, 0.27, 1.0)
            mountain.position = SIMD3(Float(mountainPosition.x), 12, Float(mountainPosition.z))
            root.addChild(mountain)

            let center = SFOAirportWorldData.localPosition(for: SFOAirportWorldData.downtown)
            for index in 0..<24 {
                let lane = index % 7
                let row = index / 7
                let height = Float(90 + ((index * 47) % 310))
                let building = ModelEntity(
                    mesh: .generateBox(
                        width: Float(48 + (index % 3) * 22),
                        height: height,
                        depth: Float(52 + (index % 4) * 14)
                    ),
                    materials: [buildingMaterial(night: false, accent: index.isMultiple(of: 8))]
                )
                building.position = SIMD3(
                    Float(center.x) + Float(lane - 3) * 90,
                    height / 2,
                    Float(center.z) + Float(row - 2) * 105
                )
                root.addChild(building)
                skyline.append(building)
            }
        }

        private func addCloudDeck() {
            let material = SimpleMaterial(
                color: UIColor.white.withAlphaComponent(0.72),
                roughness: 1,
                isMetallic: false
            )
            for index in 0..<10 {
                let cloud = ModelEntity(mesh: .generateSphere(radius: Float(110 + (index % 4) * 35)),
                                        materials: [material])
                cloud.scale = SIMD3(1.75, 0.34, 1.0)
                cloud.position = SIMD3(Float((index % 5) - 2) * 310,
                                       Float(430 + (index % 3) * 105),
                                       Float(index / 5) * -430)
                cloudRoot.addChild(cloud)
                clouds.append(cloud)
            }
            root.addChild(cloudRoot)
        }

        private func updateBuildings(isNight: Bool) {
            for (index, building) in airportBuildings.enumerated() {
                building.model?.materials = [buildingMaterial(night: isNight, accent: index.isMultiple(of: 3))]
            }
            for (index, building) in skyline.enumerated() {
                building.model?.materials = [buildingMaterial(night: isNight, accent: index.isMultiple(of: 8))]
            }
        }

        private func runwayMaterial(wet: Bool, night: Bool) -> SimpleMaterial {
            let color: UIColor
            if night { color = UIColor(red: 0.045, green: 0.052, blue: 0.065, alpha: 1) }
            else if wet { color = UIColor(red: 0.075, green: 0.095, blue: 0.11, alpha: 1) }
            else { color = UIColor(red: 0.14, green: 0.15, blue: 0.16, alpha: 1) }
            return SimpleMaterial(color: color, roughness: wet ? 0.18 : 0.78, isMetallic: wet)
        }

        private func waterMaterial(night: Bool) -> SimpleMaterial {
            let color = night
                ? UIColor(red: 0.015, green: 0.07, blue: 0.12, alpha: 1)
                : UIColor(red: 0.08, green: 0.36, blue: 0.52, alpha: 1)
            // Without an image-based lighting probe a metallic surface reflects
            // black. A moderately rough dielectric still reads as water while
            // remaining reliable in the simulator and offline on device.
            return SimpleMaterial(color: color, roughness: 0.28, isMetallic: false)
        }

        private func groundMaterial(night: Bool) -> SimpleMaterial {
            let color = night
                ? UIColor(red: 0.035, green: 0.07, blue: 0.045, alpha: 1)
                : UIColor(red: 0.15, green: 0.29, blue: 0.17, alpha: 1)
            return SimpleMaterial(color: color, roughness: 0.96, isMetallic: false)
        }

        private func buildingMaterial(night: Bool, accent: Bool) -> SimpleMaterial {
            let color: UIColor
            if night {
                color = accent
                    ? UIColor(red: 0.62, green: 0.48, blue: 0.20, alpha: 1)
                    : UIColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1)
            } else {
                color = accent
                    ? UIColor(red: 0.66, green: 0.70, blue: 0.72, alpha: 1)
                    : UIColor(red: 0.35, green: 0.39, blue: 0.41, alpha: 1)
            }
            return SimpleMaterial(color: color, roughness: 0.74, isMetallic: false)
        }

        private func radians(_ degrees: Double) -> Float {
            Float(degrees * .pi / 180)
        }
    }
}
