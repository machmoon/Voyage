import XCTest
@testable import Voyage

final class WeatherMappingTests: XCTestCase {

    // MARK: WMO code mapping (Open-Meteo)

    func testClearCodes() {
        XCTAssertEqual(WeatherService.condition(forWMOCode: 0), .clear)
        XCTAssertEqual(WeatherService.condition(forWMOCode: 1), .clear)
    }

    func testCloudCoverOverridesNominallyClearCodes() {
        XCTAssertEqual(WeatherService.condition(forWMOCode: 0, cloudCover: 90), .cloudy)
        XCTAssertEqual(WeatherService.condition(forWMOCode: 1, cloudCover: 85), .cloudy)
        XCTAssertEqual(WeatherService.condition(forWMOCode: 0, cloudCover: 20), .clear)
    }

    func testCloudCodes() {
        XCTAssertEqual(WeatherService.condition(forWMOCode: 2), .partlyCloudy)
        XCTAssertEqual(WeatherService.condition(forWMOCode: 3), .cloudy)
    }

    func testFogCodes() {
        XCTAssertEqual(WeatherService.condition(forWMOCode: 45), .fog)
        XCTAssertEqual(WeatherService.condition(forWMOCode: 48), .fog)
    }

    func testRainCodes() {
        for code in [51, 55, 61, 63, 65, 67, 80, 82] {
            XCTAssertEqual(WeatherService.condition(forWMOCode: code), .rain, "code \(code)")
        }
    }

    func testSnowCodes() {
        for code in [71, 73, 75, 77, 85, 86] {
            XCTAssertEqual(WeatherService.condition(forWMOCode: code), .snow, "code \(code)")
        }
    }

    func testStormCodes() {
        for code in [95, 96, 99] {
            XCTAssertEqual(WeatherService.condition(forWMOCode: code), .storm, "code \(code)")
        }
    }

    func testUnknownCodesFallBackToClear() {
        XCTAssertEqual(WeatherService.condition(forWMOCode: 42), .clear)
        XCTAssertEqual(WeatherService.condition(forWMOCode: -1), .clear)
        XCTAssertEqual(WeatherService.condition(forWMOCode: 1000), .clear)
    }

    // MARK: Scene parameters

    func testCloudAmountOrdering() {
        XCTAssertLessThan(SkyCondition.clear.cloudAmount, SkyCondition.partlyCloudy.cloudAmount)
        XCTAssertLessThan(SkyCondition.partlyCloudy.cloudAmount, SkyCondition.cloudy.cloudAmount)
    }

    func testPrecipitationFlags() {
        XCTAssertTrue(SkyCondition.rain.isPrecipitating)
        XCTAssertTrue(SkyCondition.storm.isPrecipitating)
        XCTAssertTrue(SkyCondition.snow.isPrecipitating)
        XCTAssertFalse(SkyCondition.cloudy.isPrecipitating)
        XCTAssertFalse(SkyCondition.fog.isPrecipitating)
        XCTAssertFalse(SkyCondition.clear.isPrecipitating)
    }

    func testEveryConditionSpeaksAndDecodes() throws {
        let all: [SkyCondition] = [.clear, .partlyCloudy, .cloudy, .fog, .rain, .storm, .snow]
        for condition in all {
            XCTAssertFalse(condition.spokenDescription.isEmpty)
            let data = try JSONEncoder().encode(condition)
            XCTAssertEqual(try JSONDecoder().decode(SkyCondition.self, from: data), condition)
        }
    }
}
