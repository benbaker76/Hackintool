//
//  AppDelegate.h
//  Hackintool
//
//  Created by Ben Baker on 6/19/18.
//  Copyright (c) 2018 Ben Baker. All rights reserved.
//

#ifndef AppDelegate_h
#define AppDelegate_h

#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>
#import "PCIMonitor.h"

#define VEN_AMD_ID              0x1002
#define VEN_INTEL_ID            0x8086
#define VEN_NVIDIA_ID           0x10DE

enum BootloaderType
{
	kBootloaderAutoDetect,
	kBootloaderClover,
	kBootloaderOpenCore
};

@interface IntConvert : NSObject
{
@public
	uint32_t Index;
	NSString *Name;
	NSString *StringValue;
	uint8_t Uint8Value;
	uint32_t Uint32Value;
	uint64_t Uint64Value;
	uint32_t MemoryInBytes;
	uint32_t DecimalValue;
}

-(id) init:(uint32_t )index name:(NSString *)name stringValue:(NSString *)stringValue;

@end

typedef struct
{
	NSString *IntelGen;
	NSString *PlatformID;
	bool KextsToPatchHex;
	bool KextsToPatchBase64;
	bool DeviceProperties;
	bool iASLDSLSource;
	uint32_t DetectedBootloader;
	uint32_t SelectedBootloader;
	bool AutoDetectChanges;
	bool UseAllDataMethod;
	bool PatchAll;
	bool PatchConnectors;
	bool PatchVRAM;
	bool PatchGraphicDevice;
	bool PatchAudioDevice;
	bool PatchPCIDevices;
	bool PatchEDID;
	bool ApplyCurrentPatches;
	bool DVMTPrealloc32MB;
	bool VRAM2048MB;
	bool DisableeGPU;
	bool EnableHDMI20;
	bool DPtoHDMI;
	bool UseIntelHDMI;
	bool GfxYTileFix;
	bool HotplugRebootFix;
	bool HDMIInfiniteLoopFix;
	bool DPCDMaxLinkRateFix;
	uint32_t DPCDMaxLinkRate;
	bool FBPortLimit;
	uint32_t FBPortCount;
	bool InjectDeviceID;
	bool USBPortLimit;
	bool SpoofAudioDeviceID;
	bool InjectFakeIGPU;
	bool ShowInstalledOnly;
	bool LSPCON_Enable;
	bool LSPCON_AutoDetect;
	bool LSPCON_Connector;
	uint32_t LSPCON_ConnectorIndex;
	bool LSPCON_PreferredMode;
	uint32_t LSPCON_PreferredModeIndex;
	bool AII_EnableHWP;
	bool AII_LogCStates;
	bool AII_LogIGPU;
	bool AII_LogIPGStyle;
	bool AII_LogIntelRegs;
	bool AII_LogMSRs;
} Settings;

typedef struct
{
	NSString *Name;
	NSString *LastVersionDownloaded;
	NSString *LastDownloadWarned;
	NSString *LastCheckTimestamp;
	NSString *ScheduledCheckInterval;
	NSString *LatestReleaseURL;
	NSString *LatestDownloadURL;
	NSString *LatestVersion;
	NSString *BootedVersion;
	NSString *InstalledVersion;
	NSString *DownloadPath;
	NSString *FileNameMatch;
	NSString *SuggestedFileName;
	NSString *IconName;
} BootloaderInfo;

@class AudioDevice;

@interface AppDelegate : NSResponder <NSApplicationDelegate, NSURLConnectionDelegate, NSURLConnectionDataDelegate, NSTableViewDataSource, NSTabViewDelegate, NSOutlineViewDelegate, NSWindowDelegate, NSURLConnectionDelegate, NSURLDownloadDelegate, NSMenuDelegate, NSTextFieldDelegate, NSTextViewDelegate, NSComboBoxDelegate, NSSplitViewDelegate, PCIMonitorDelegate>
{
	NSString *_fileName;
	BOOL _gatekeeperDisabled;
	
	NSArray *_tableViewArray;
	
	NSMutableArray *_audioDevicesArray;
	NSMutableArray *_nodeArray;
	
	NSMutableArray *_usbControllersArray;
	NSDictionary *_usbConfigurationDictionary;
	
	//NSMutableArray *_displaysArray;
	
	NSString *_intelGenString;
	uint32_t _gpuDeviceID;
	uint32_t _gpuVendorID;
	mach_vm_size_t _vramSize;
	mach_vm_size_t _vramFree;
	uint32_t _platformID;
	NSString *_serialNumber;
	NSString *_generateSerialNumber;
	
	NSMutableDictionary *_intelPlatformIDsDictionary_10_13_6;
	NSMutableDictionary *_intelPlatformIDsDictionary_10_14;
	NSDictionary *_intelDeviceIDsDictionary;
	NSDictionary *_fbDriversDictionary;
	NSDictionary *_intelSpoofAudioDictionary;
	NSArray *_audioCodecsArray;
	NSArray *_systemsArray;
	NSDictionary *_audioVendorsDictionary;
	NSMutableArray *_kextsArray;
	NSMutableArray *_installedKextsArray;
	NSMutableDictionary *_installedKextVersionDictionary;
	
	NSMutableArray *_bootloaderPatchArray;
	NSMutableArray *_systemConfigsArray;
	
	NSMutableDictionary *_pciVendorsDictionary;
	NSMutableDictionary *_pciClassesDictionary;
	NSMutableArray *_pciDevicesArray;
	PCIMonitor *_pciMonitor;
	
	NSMutableArray *_networkInterfacesArray;
	NSMutableArray *_bluetoothDevicesArray;
	NSMutableArray *_graphicDevicesArray;
	NSMutableArray *_storageDevicesArray;
	
	NSMutableDictionary *_systemWidePowerSettings;
	NSMutableDictionary *_currentPowerSettings;
	
	// Bootloader Info
	BootloaderInfo _cloverInfo;
	BootloaderInfo _openCoreInfo;
	BootloaderInfo *_bootloaderInfo;
	
	BOOL _forcedUpdate;
	NSURLConnection *_connection;
	NSURLDownload *_download;
	
	NSString *_bootloaderDeviceUUID;
	NSString *_bootloaderDirPath;
	
	NSColor *_greenColor;
	NSColor *_redColor;
	NSColor *_orangeColor;
}

@property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet NSToolbar *toolbar;
@property (assign) IBOutlet NSTabView *tabView;
@property (assign) IBOutlet NSComboBox *intelGenComboBox;
@property (assign) IBOutlet NSComboBox *platformIDComboBox;
@property (assign) IBOutlet NSTableView *framebufferInfoTableView;
@property (assign) IBOutlet NSTableView *framebufferFlagsTableView;
@property (assign) IBOutlet NSTableView *connectorInfoTableView;
@property (assign) IBOutlet NSTableView *connectorFlagsTableView;
@property (assign) IBOutlet NSButton *headlessButton;
// Import KextsToPatch Window
@property (assign) IBOutlet NSWindow *importKextsToPatchWindow;
@property (assign) IBOutlet NSTextField *findTextField;
@property (assign) IBOutlet NSTextField *replaceTextField;
// Info Window
@property (assign) IBOutlet NSWindow *infoWindow;
@property (assign) IBOutlet NSTextView *infoTextView;
@property (assign) IBOutlet NSTextField *infoTextField;
// Authorization
@property (assign) IBOutlet NSButton *authorizationButton;
// Bootloader
@property (assign) IBOutlet NSImageView *bootloaderImageView;
@property (assign) IBOutlet NSTableView *bootloaderInfoTableView;
@property (assign) IBOutlet NSTableView *bootloaderPatchTableView;
// NVRAM
@property (assign) IBOutlet NSTableView *nvramTableView;
@property (assign) IBOutlet NSTextView *nvramValueTextView;
@property (assign) IBOutlet NSWindow *createNVRAMVariableWindow;
@property (assign) IBOutlet NSComboBox *createNVRAMComboBox;
@property (assign) IBOutlet NSButton *createNVRAMStringButton;
@property (assign) IBOutlet NSTextView *createNVRAMTextView;
// Installed
@property (assign) IBOutlet NSTableView *kextsTableView;
@property (assign) IBOutlet NSButton *showInstalledOnlyButton;
@property (assign) IBOutlet NSMenu *installMenu;
@property (assign) IBOutlet NSTextView *compileOutputTextView;
@property (assign) IBOutlet NSProgressIndicator *compileProgressIndicator;
// Display Info
@property (assign) IBOutlet NSTableView *displayInfoTableView;
// System Info
@property (assign) IBOutlet NSOutlineView *infoOutlineView;
@property (assign) IBOutlet NSTableView *generateSerialInfoTableView;
@property (assign) IBOutlet NSTableView *modelInfoTableView;
// FB Info
@property (assign) IBOutlet NSTableView *selectedFBInfoTableView;
@property (assign) IBOutlet NSTableView *currentFBInfoTableView;
@property (assign) IBOutlet NSTableView *vramInfoTableView;
// Framebuffer Info
@property (retain) NSDictionary *intelGPUsDictionary;
@property (retain) NSDictionary *intelModelsDictionary;
// Displays
@property (assign) IBOutlet NSTableView *displaysTableView;
@property (assign) IBOutlet NSTableView *resolutionsTableView;
@property (assign) IBOutlet NSButton *fixMonitorRangesButton;
@property (assign) IBOutlet NSButton *injectAppleInfoButton;
@property (assign) IBOutlet NSButton *forceRGBModeButton;
@property (assign) IBOutlet NSButton *patchColorProfileButton;
@property (assign) IBOutlet NSButton *ignoreDisplayPrefsButton;
@property (assign) IBOutlet NSPopUpButton *edidPopupButton;
@property (assign) IBOutlet NSComboBox *iconComboBox;
@property (assign) IBOutlet NSComboBox *resolutionComboBox;
// Sound
@property (assign) IBOutlet NSTableView *audioDevicesTableView1;
@property (assign) IBOutlet NSOutlineView *pinConfigurationOutlineView;
@property (assign) IBOutlet NSTableView *audioInfoTableView;
// USB
@property (assign) IBOutlet NSTableView *usbControllersTableView;
@property (assign) IBOutlet NSTableView *usbPortsTableView;
// Disks
@property (assign) IBOutlet NSTableView *efiPartitionsTableView;
@property (assign) IBOutlet NSTableView *partitionSchemeTableView;
@property (assign) IBOutlet NSMenu *mountMenu;
// PCI
@property (assign) IBOutlet NSTableView *pciDevicesTableView;
// Info
@property (assign) IBOutlet NSTableView *networkInterfacesTableView;
@property (assign) IBOutlet NSTableView *bluetoothDevicesTableView;
@property (assign) IBOutlet NSTableView *graphicDevicesTableView;
@property (assign) IBOutlet NSTableView *audioDevicesTableView2;
@property (assign) IBOutlet NSTableView *storageDevicesTableView;
@property (assign) IBOutlet NSComboBox *generateSerialModelInfoComboBox;
@property (assign) IBOutlet NSComboBox *modelInfoComboBox;
// Power
@property (assign) IBOutlet NSTableView *powerSettingsTableView;
// Tools
@property (assign) IBOutlet NSTextView *toolsOutputTextView;
@property (assign) IBOutlet NSButton *aiiEnableHWP;
@property (assign) IBOutlet NSButton *aiiLogCStates;
@property (assign) IBOutlet NSButton *aiiLogIGPU;
@property (assign) IBOutlet NSButton *aiiLogIPGStyle;
@property (assign) IBOutlet NSButton *aiiLogIntelRegs;
@property (assign) IBOutlet NSButton *aiiLogMSRs;
// Calculator
@property (assign) IBOutlet NSTextField *calcHexSequenceTextField;
@property (assign) IBOutlet NSTextField *calcHexSequenceReverseTextField;
@property (assign) IBOutlet NSTextField *calcBase64SequenceTextField;
@property (assign) IBOutlet NSTextField *calcASCIISequenceTextField;
@property (assign) IBOutlet NSTextField *calcHexValueTextField;
@property (assign) IBOutlet NSTextField *calcDecimalValueTextField;
@property (assign) IBOutlet NSTextField *calcOctalValueTextField;
@property (assign) IBOutlet NSTextField *calcBinaryValueTextField;
// Logs
@property (assign) IBOutlet NSTextView *bootLogTextView;
@property (assign) IBOutlet NSTextView *liluLogTextView;
@property (assign) IBOutlet NSTextView *systemLogTextView;
@property (assign) IBOutlet NSButton *lastBootLogButton;
@property (assign) IBOutlet NSComboBox *processLogComboBox;
@property (assign) IBOutlet NSComboBox *containsLogComboBox;
// Patch
@property (assign) IBOutlet NSButton *kextsToPatchHexPatchRadioButton;
@property (assign) IBOutlet NSButton *kextsToPatchBase64PatchRadioButton;
@property (assign) IBOutlet NSButton *devicePropertiesPatchRadioButton;
@property (assign) IBOutlet NSButton *iASLDSLSourcePatchRadioButton;
@property (assign) IBOutlet NSComboBox *bootloaderComboBox;
@property (assign) IBOutlet NSButton *autoDetectChangesButton;
@property (assign) IBOutlet NSButton *allPatchButton;
@property (assign) IBOutlet NSButton *useAllDataMethodButton;
@property (assign) IBOutlet NSButton *connectorsPatchButton;
@property (assign) IBOutlet NSButton *vramPatchButton;
@property (assign) IBOutlet NSButton *graphicDevicePatchButton;
@property (assign) IBOutlet NSButton *audioDevicePatchButton;
@property (assign) IBOutlet NSButton *pciDevicesPatchButton;
@property (assign) IBOutlet NSButton *edidPatchButton;
@property (assign) IBOutlet NSButton *dvmtPrealloc32MB;
@property (assign) IBOutlet NSButton *vram2048MB;
@property (assign) IBOutlet NSButton *disableeGPUButton;
@property (assign) IBOutlet NSButton *enableHDMI20Button;
@property (assign) IBOutlet NSButton *dptoHDMIButton;
@property (assign) IBOutlet NSButton *useIntelHDMIButton;
@property (assign) IBOutlet NSButton *gfxYTileFixButton;
@property (assign) IBOutlet NSButton *hotplugRebootFixButton;
@property (assign) IBOutlet NSButton *hdmiInfiniteLoopFixButton;
@property (assign) IBOutlet NSButton *dpcdMaxLinkRateButton;
@property (assign) IBOutlet NSComboBox *dpcdMaxLinkRateComboBox;
@property (assign) IBOutlet NSButton *fbPortLimitButton;
@property (assign) IBOutlet NSComboBox *fbPortLimitComboBox;
@property (assign) IBOutlet NSButton *injectDeviceIDButton;
@property (assign) IBOutlet NSComboBox *injectDeviceIDComboBox;
@property (assign) IBOutlet NSButton *spoofAudioDeviceIDButton;
@property (assign) IBOutlet NSButton *injectFakeIGPUButton;
@property (assign) IBOutlet NSButton *usbPortLimitButton;
@property (assign) IBOutlet NSButton *generatePatchButton;
@property (assign) IBOutlet NSTextView *patchOutputTextView;
@property (assign) IBOutlet NSButton *lspconEnableDriverButton;
@property (assign) IBOutlet NSButton *lspconAutoDetectRadioButton;
@property (assign) IBOutlet NSButton *lspconConnectorRadioButton;
@property (assign) IBOutlet NSComboBox *lspconConnectorComboBox;
@property (assign) IBOutlet NSButton *lspconPreferredModeButton;
@property (assign) IBOutlet NSComboBox *lspconPreferredModeComboBox;
// Other
@property (assign) IBOutlet NSButton *headsoftLogoButton;
// Menus
@property (assign) IBOutlet NSMenuItem *importIORegNativeMenuItem;
@property (assign) IBOutlet NSMenuItem *importIORegPatchedMenuItem;
@property (assign) IBOutlet NSMenuItem *currentVersionMenuItem;
@property (assign) IBOutlet NSMenuItem *macOS_10_13_6_MenuItem;
@property (assign) IBOutlet NSMenuItem *macOS_10_14_MenuItem;
@property (assign) IBOutlet NSMenuItem *importKextsToPatchMenuItem;
@property (assign) IBOutlet NSMenuItem *azulPatcher4600MenuItem;
@property (assign) IBOutlet NSMenuItem *applyCurrentPatchesMenuItem;
@property (assign) IBOutlet NSMenu *systemConfigsMenu;

@property (retain) NSString *efiBootDeviceUUID;
@property (retain) NSMutableDictionary *nvramDictionary;
@property (retain) NSMutableArray *disksArray;
@property (retain) NSMutableArray *systemInfoArray;
@property (retain) NSMutableArray *serialInfoArray;
@property (retain) NSMutableArray *iMessageKeysArray;
@property (retain) NSMutableDictionary *gpuInfoDictionary;
@property (retain) NSMutableArray *infoArray;
@property (retain) NSMutableArray *generateSerialInfoArray;
@property (retain) NSMutableArray *modelInfoArray;
@property (retain) NSMutableArray *selectedFBInfoArray;
@property (retain) NSMutableArray *currentFBInfoArray;
@property (retain) NSMutableArray *vramInfoArray;
@property (retain) NSMutableArray *framebufferInfoArray;
@property (retain) NSMutableArray *framebufferFlagsArray;
@property (retain) NSMutableArray *connectorFlagsArray;
@property (retain) NSMutableArray *displaysArray;
@property (retain) NSMutableArray *displayInfoArray;
@property (retain) NSMutableArray *audioInfoArray;
@property (retain) NSMutableArray *usbPortsArray;
@property (retain) NSMutableArray *bootloaderInfoArray;
@property (readonly) NSMutableArray *pciDevicesArray;
@property (readonly) uint8_t *originalFramebufferList;
@property (readonly) uint8_t *modifiedFramebufferList;
@property (readonly) uint32_t framebufferSize;
@property (readonly) uint32_t framebufferCount;
@property (readonly) NSString *modelIdentifier;
@property (readonly) NSString *gpuModel;
@property (readonly) NSString *bootLog;
@property (readonly) NSString *bootloaderDirPath;
@property (readonly) uint32_t alcLayoutID;
@property Settings settings;

// Bootloader Download
@property (assign) IBOutlet NSWindow *hasUpdateWindow;
@property (assign) IBOutlet NSImageView *hasUpdateImageView;
@property (assign) IBOutlet NSTextField *hasUpdateTextField;

@property (assign) IBOutlet NSWindow *noUpdatesWindow;
@property (assign) IBOutlet NSImageView *noUpdatesImageView;
@property (assign) IBOutlet NSTextField *noUpdatesTextField;

@property (assign) IBOutlet NSWindow *progressWindow;
@property (assign) IBOutlet NSButton *progressCancelButton;
@property (assign) IBOutlet NSImageView *progressImageView;
@property (assign) IBOutlet NSTextField *progressMessageTextField;
@property (assign) IBOutlet NSTextField *progressTitleTextField;
@property (assign) IBOutlet NSLevelIndicator *progressLevelIndicator;
@property (assign) IBOutlet NSProgressIndicator *progressIndicator;

- (void)refreshDisks;
- (void)updateSettingsGUI;
- (void)addUSBDevice:(uint32_t)controllerID controllerLocationID:(uint32_t)controllerLocationID locationID:(uint32_t)locationID port:(uint32_t)port deviceName:(NSString *)deviceName devSpeed:(uint8_t)devSpeed;
- (void)removeUSBDevice:(uint32_t)controllerID controllerLocationID:(uint32_t)controllerLocationID locationID:(uint32_t)locationID port:(uint32_t)port;
- (uint32_t)getGPUDeviceID:(uint32_t)platformID;
- (NSString *)getGPUString:(uint32_t)platformID;
- (NSString *)getModelString:(uint32_t)platformID;
- (void)addToList:(NSMutableArray *)list name:(NSString *)name value:(NSString *)value;
- (bool)tryGetNearestModel:(NSArray *)modelArray modelIdentifier:(NSString *)modelIdentifier nearestModelIdentifier:(NSString **)nearestModelIdentifier;
- (bool)showAlert:(NSString *)message text:(NSString *)text;
- (bool)framebufferHasModified;
- (uint32_t)getPlatformID;
- (bool)spoofAudioDeviceID:(uint32_t)deviceID newDeviceID:(uint32_t *)newDeviceID;
- (bool)getDeviceIDArray:(NSMutableArray **)deviceIDArray;
- (void)appendTextViewWithFormat:(NSTextView *)textView format:(NSString *)format, ...;
- (void)appendTextView:(NSTextView *)textView text:(NSString *)text;
- (void)getPCIConfigDictionary:(NSMutableDictionary *)configDictionary;
- (void)appendTabCount:(uint32_t)tabCount outputString:(NSMutableString *)outputString;
- (void)appendDSLString:(uint32_t)tabCount outputString:(NSMutableString *)outputString value:(NSString *)value;
- (void)appendDSLValue:(uint32_t)tabCount outputString:(NSMutableString *)outputString name:(NSString *)name value:(id)value;
- (bool)hasNVIDIAGPU;
- (bool)hasAMDGPU;
- (bool)hasIntelGPU;
- (bool)hasGFX0;
- (bool)hasIGPU;
- (bool)hasGPU:(uint32_t)vID;
- (bool)isBootloaderOpenCore;
- (bool)isConnectorHeadless;
- (NSString *)getIORegName:(NSString *)ioregName;
- (bool)tryGetACPIPath:(NSString *)ioregName acpiPath:(NSString **)acpiPath;
- (bool)tryGetGPUDeviceDictionary:(NSMutableDictionary **)pciDeviceDictionary;
- (bool)tryGetPCIDeviceDictionaryFromIORegName:(NSString *)name pciDeviceDictionary:(NSMutableDictionary **)pciDeviceDictionary;
- (bool)tryGetPCIDeviceDictionaryFromClassCode:(NSNumber *)code pciDeviceDictionary:(NSMutableDictionary **)pciDeviceDictionary;
- (bool)tryGetAudioController:(NSNumber *)deviceID vendorID:(NSNumber *)vendorID audioDevice:(AudioDevice *)foundAudioDevice;
- (bool)isAppleHDAAudioDevice:(AudioDevice *)audioDevice;
- (bool)isVoodooHDAAudioDevice:(AudioDevice *)audioDevice;
- (IBAction)generateAudioCodecsInfo:(id)sender;
- (IBAction)displaySettingsChanged:(id)sender;
- (IBAction)platformIDButtonClicked:(id)sender;
- (IBAction)patchButtonClicked:(id)sender;
- (IBAction)lspconButtonClicked:(id)sender;
- (IBAction)patchComboBoxDidChange:(id)sender;
- (IBAction)bootloaderComboBoxDidChange:(id)sender;
- (IBAction)infoComboBoxDidChange:(id)sender;
- (IBAction)generateSerialComboBoxDidChange:(id)sender;
- (IBAction)generateSerialButtonDidChange:(id)sender;
- (IBAction)generatePatchButtonClicked:(id)sender;
- (IBAction)headsoftLogoButtonClicked:(id)sender;
- (IBAction)vramInfoChanged:(id)sender;
- (IBAction)openDocument:(id)sender;
- (IBAction)fileImportMenuItemClicked:(id)sender;
- (IBAction)fileExportBootloaderConfig:(id)sender;
- (IBAction)fileExportFramebufferText:(id)sender;
- (IBAction)fileExportFramebufferBinary:(id)sender;
- (IBAction)fileQuit:(id)sender;
- (IBAction)infoPrint:(id)sender;
- (IBAction)framebufferMenuItemClicked:(id)sender;
- (IBAction)patchMenuItemClicked:(id)sender;
- (IBAction)audioButtonClicked:(id)sender;
- (IBAction)usbButtonClicked:(id)sender;
- (IBAction)pciButtonClicked:(id)sender;
- (IBAction)infoButtonClicked:(id)sender;
- (IBAction)diskMountButtonClicked:(id)sender;
- (IBAction)diskOpenButtonClicked:(id)sender;
- (IBAction)mountMenuClicked:(id)sender;
- (IBAction)installMenuClicked:(id)sender;
- (IBAction)pciMenuClicked:(id)sender;
- (IBAction)infoMenuClicked:(id)sender;
- (IBAction)logButtonClicked:(id)sender;
- (IBAction)displayButtonClicked:(id)sender;
- (IBAction)framebufferInfoChanged:(id)sender;
- (IBAction)framebufferFlagsChanged:(id)sender;
- (IBAction)connectorInfoChanged:(id)sender;
- (IBAction)powerSettingsChanged:(id)sender;
- (IBAction)powerButtonClicked:(id)sender;
- (IBAction)toolsButtonClicked:(id)sender;
- (IBAction)nvramChanged:(id)sender;
- (IBAction)nvramValueTableViewChanged:(id)sender;
- (IBAction)nvramButtonClicked:(id)sender;
- (IBAction)nvramRadioButtonClicked:(id)sender;
- (IBAction)dsdtRenameChanged:(id)sender;
- (IBAction)audioTableViewSelected:(id)sender;
- (IBAction)connectorFlagsChanged:(id)sender;
- (IBAction)usbNameChanged:(id)sender;
- (IBAction)usbCommentChanged:(id)sender;
- (IBAction)usbConnectorChanged:(id)sender;
- (IBAction)displaysChanged:(id)sender;
- (IBAction)resolutionsChanged:(id)sender;
- (IBAction)cancelButtonClicked:(id)sender;
- (IBAction)okButtonClicked:(id)sender;
- (IBAction)payPalButtonClicked:(id)sender;
- (IBAction)installedButtonClicked:(id)sender;
- (IBAction)progressCancelButtonClicked:(id)sender;
- (IBAction)bootloaderButtonClicked:(id)sender;
- (IBAction)lockButtonClicked:(id)sender;
- (IBAction)toolbarClicked:(id)sender;
- (IBAction)outputMenuClicked:(id)sender;
- (IBAction)pciViewButtonClicked:(id)sender;
- (IBAction)appleIntelInfoButtonClicked:(id)sender;
- (void) updateAuthorization;

@end

#endif
