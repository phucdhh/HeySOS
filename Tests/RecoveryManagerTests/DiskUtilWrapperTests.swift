// DiskUtilWrapperTests.swift
// HeySOS — Unit Tests

import Testing
@testable import HeySOSCore

@Suite("DiskUtil Wrapper")
struct DiskUtilWrapperTests {

    @Test("listDevices returns at least one disk")
    func listDevicesReturnsAtLeastOneDisk() throws {
        let devices = try DiskUtilWrapper.listDevices()
        #expect(!devices.isEmpty, "Expected at least one disk (internal boot disk)")
    }

    @Test("At least one internal (non-external) device is present")
    func internalBootDiskPresent() throws {
        let devices = try DiskUtilWrapper.listDevices()
        let hasInternal = devices.contains { !$0.isExternal }
        #expect(hasInternal, "Expected at least one internal device")
    }

    @Test("All device IDs start with /dev/")
    func deviceIDsStartWithSlashDev() throws {
        let devices = try DiskUtilWrapper.listDevices()
        for device in devices {
            #expect(device.id.hasPrefix("/dev/"), "Device ID '\(device.id)' should start with /dev/")
        }
    }

    @Test("All device sizes are positive")
    func deviceSizesArePositive() throws {
        let devices = try DiskUtilWrapper.listDevices()
        for device in devices {
            #expect(device.size > 0, "Device '\(device.id)' has zero size")
        }
    }
}

// MARK: - StorageDevice Tests

@Suite("StorageDevice Model")
struct StorageDeviceTests {

    @Test("formattedSize shows GB for large devices")
    func formattedSizeGigabytes() {
        let device = StorageDevice(
            id: "/dev/disk2",
            name: "Test",
            size: 64_000_000_000,
            fileSystem: "exFAT",
            isExternal: true,
            mountPoint: "/Volumes/Test",
            mediaType: .sdCard
        )
        #expect(device.formattedSize.contains("GB"))
    }

    @Test("displayTitle contains name and size")
    func displayTitleContainsNameAndSize() {
        let device = StorageDevice(
            id: "/dev/disk2",
            name: "SONY SD",
            size: 64_000_000_000,
            fileSystem: "exFAT",
            isExternal: true,
            mountPoint: nil,
            mediaType: .sdCard
        )
        #expect(device.displayTitle.contains("SONY SD"))
        #expect(device.displayTitle.contains("GB"))
    }
}

