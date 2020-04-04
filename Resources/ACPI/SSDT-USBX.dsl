//
// USB Power Propertes for Sierra
//
// Note: Only used when using an SMBIOS without power properties
//  in IOUSBHostFamily Info.plist
//

DefinitionBlock ("", "SSDT", 2, "hack", "_USBX", 0)
{
    Device(_SB.USBX)
    {
        Name(_ADR, 0)
        Method (_DSM, 4)
        {
            If (!Arg2) { Return (Buffer() { 0x03 } ) }
            Return (Package()
            {
                // from iMac17,1
                "kUSBSleepPortCurrentLimit", 2100,
                "kUSBSleepPowerSupply", 5100,
                "kUSBWakePortCurrentLimit", 2100,
                "kUSBWakePowerSupply", 5100,
            })
        }
    }
}
