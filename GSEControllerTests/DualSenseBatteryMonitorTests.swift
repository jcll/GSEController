import Foundation
import Testing
@testable import GSEController

@Suite struct DualSenseBatteryMonitorTests {

    // MARK: - parseBatteryByte

    @Test func levelZeroReturnsNil() {
        #expect(DualSenseBatteryMonitor.parseBatteryByte(0x00) == nil)
    }

    @Test func levelAboveTenReturnsNil() {
        // level nibble = 11 (0x0B), should be invalid
        #expect(DualSenseBatteryMonitor.parseBatteryByte(0x0B) == nil)
    }

    @Test func levelOneGivesFivePercent() {
        let result = DualSenseBatteryMonitor.parseBatteryByte(0x01)
        #expect(result != nil)
        #expect(result!.level == Float(min(1 * 10 + 5, 100)) / 100.0)
        #expect(result!.charging == false)
    }

    @Test func levelTenGivesOneHundredPercent() {
        let result = DualSenseBatteryMonitor.parseBatteryByte(0x0A)
        #expect(result != nil)
        #expect(result!.level == 1.0)
    }

    @Test func chargingNibbleOneIsCharging() {
        // upper nibble = 1 (charging), lower nibble = 5
        let byte: UInt8 = 0x15
        let result = DualSenseBatteryMonitor.parseBatteryByte(byte)
        #expect(result?.charging == true)
    }

    @Test func chargingNibbleTwoIsCharging() {
        // upper nibble = 2 (full/charging), lower nibble = 5
        let byte: UInt8 = 0x25
        let result = DualSenseBatteryMonitor.parseBatteryByte(byte)
        #expect(result?.charging == true)
    }

    @Test func chargingNibbleZeroIsNotCharging() {
        // upper nibble = 0 (discharging), lower nibble = 5
        let byte: UInt8 = 0x05
        let result = DualSenseBatteryMonitor.parseBatteryByte(byte)
        #expect(result?.charging == false)
    }

    @Test func percentageFormulaIsCorrect() {
        // level = 7: min(7*10+5, 100)/100 = 0.75
        let result = DualSenseBatteryMonitor.parseBatteryByte(0x07)
        #expect(result?.level == 0.75)
    }
}
