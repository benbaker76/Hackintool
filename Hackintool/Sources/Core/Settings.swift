//
//  Settings.swift
//  Hackintool
//
//  User preferences, stored in UserDefaults under the same keys the
//  Objective-C app used so existing settings carry over.
//  Settings saved under the old com.Headsoft.Hackintool bundle ID are copied over once.
//

import Foundation

@propertyWrapper
struct Default<Value> {
	let key: String
	let defaultValue: Value

	init(_ key: String, _ defaultValue: Value) {
		self.key = key
		self.defaultValue = defaultValue
	}

	var wrappedValue: Value {
		get { return UserDefaults.standard.object(forKey: key) as? Value ?? defaultValue }
		set { UserDefaults.standard.set(newValue, forKey: key) }
	}
}

enum BootloaderChoice: Int {
	case autoDetect, clover, openCore
}

enum Settings {
	/// The bundle ID Hackintool used before moving to com.Baker76.Hackintool.
	private static let legacyDomain = "com.Headsoft.Hackintool"
	private static let migratedKey = "MigratedLegacySettings"

	/// Copies preferences from the old bundle ID's domain the first time the app runs under the
	/// new one. Sparkle's own keys (SU…) are skipped so the updater starts fresh with the new key.
	static func migrateLegacySettings() {
		let defaults = UserDefaults.standard
		guard Bundle.main.bundleIdentifier != legacyDomain, !defaults.bool(forKey: migratedKey) else { return }
		defaults.set(true, forKey: migratedKey)
		guard let legacy = defaults.persistentDomain(forName: legacyDomain) else { return }
		for (key, value) in legacy where !key.hasPrefix("SU") && defaults.object(forKey: key) == nil {
			defaults.set(value, forKey: key)
		}
	}

	// Framebuffer patching
	@Default("IntelGen", "Coffee Lake") static var intelGeneration: String
	@Default("PlatformID", "") static var platformID: String
	@Default("KextsToPatchHex", false) static var kextsToPatchHex: Bool
	@Default("KextsToPatchBase64", false) static var kextsToPatchBase64: Bool
	@Default("DeviceProperties", true) static var deviceProperties: Bool
	@Default("iASLDSLSource", false) static var iASLDSLSource: Bool
	@Default("AutoDetectChanges", true) static var autoDetectChanges: Bool
	@Default("UseAllDataMethod", false) static var useAllDataMethod: Bool
	@Default("PatchAll", false) static var patchAll: Bool
	@Default("PatchConnectors", true) static var patchConnectors: Bool
	@Default("PatchVRAM", true) static var patchVRAM: Bool
	@Default("PatchGraphicDevice", true) static var patchGraphicDevice: Bool
	@Default("PatchAudioDevice", true) static var patchAudioDevice: Bool
	@Default("PatchPCIDevices", false) static var patchPCIDevices: Bool
	@Default("PatchEDID", false) static var patchEDID: Bool
	@Default("DVMTPrealloc32MB", false) static var dvmtPrealloc32MB: Bool
	@Default("VRAM2048MB", false) static var vram2048MB: Bool
	@Default("DisableeGPU", false) static var disableeGPU: Bool
	@Default("EnableHDMI20", false) static var enableHDMI20: Bool
	@Default("DPtoHDMI", false) static var dpToHDMI: Bool
	@Default("UseIntelHDMI", true) static var useIntelHDMI: Bool
	@Default("GfxYTileFix", false) static var gfxYTileFix: Bool
	@Default("HotplugRebootFix", false) static var hotplugRebootFix: Bool
	@Default("HDMIInfiniteLoopFix", false) static var hdmiInfiniteLoopFix: Bool
	@Default("DPCDMaxLinkRateFix", false) static var dpcdMaxLinkRateFix: Bool
	@Default("DPCDMaxLinkRate", 2) static var dpcdMaxLinkRate: Int
	@Default("FBPortLimit", false) static var fbPortLimit: Bool
	@Default("FBPortCount", 2) static var fbPortCount: Int
	@Default("InjectDeviceID", false) static var injectDeviceID: Bool
	@Default("SpoofAudioDeviceID", false) static var spoofAudioDeviceID: Bool
	@Default("InjectFakeIGPU", false) static var injectFakeIGPU: Bool
	@Default("USBPortLimit", false) static var usbPortLimit: Bool
	@Default("ApplyCurrentPatches", false) static var applyCurrentPatches: Bool
	@Default("LSPCON_Enable", false) static var lspconEnable: Bool
	@Default("LSPCON_AutoDetect", true) static var lspconAutoDetect: Bool
	@Default("LSPCON_Connector", false) static var lspconConnector: Bool
	@Default("LSPCON_ConnectorIndex", 0) static var lspconConnectorIndex: Int
	@Default("LSPCON_PreferredMode", false) static var lspconPreferredMode: Bool
	@Default("LSPCON_PreferredModeIndex", 1) static var lspconPreferredModeIndex: Int

	// Bootloader
	@Default("SelectedBootloader", BootloaderChoice.autoDetect.rawValue) static var selectedBootloaderRaw: Int

	static var selectedBootloader: BootloaderChoice {
		get { return BootloaderChoice(rawValue: selectedBootloaderRaw) ?? .autoDetect }
		set { selectedBootloaderRaw = newValue.rawValue }
	}

	// Extensions
	@Default("ShowInstalledOnly", true) static var showInstalledOnly: Bool

	// Sound
	@Default("SelectedAudioDevice", 0) static var selectedAudioDevice: Int

	// AppleIntelInfo
	@Default("AII_EnableHWP", false) static var aiiEnableHWP: Bool
	@Default("AII_LogCStates", true) static var aiiLogCStates: Bool
	@Default("AII_LogIGPU", true) static var aiiLogIGPU: Bool
	@Default("AII_LogIPGStyle", true) static var aiiLogIPGStyle: Bool
	@Default("AII_LogIntelRegs", false) static var aiiLogIntelRegs: Bool
	@Default("AII_LogMSRs", true) static var aiiLogMSRs: Bool
}
