//
// Simulate Windows for _OSI calls
//
// All _OSI calls in DSDT are routed to XOSI...
// XOSI simulates "Windows 2009" (which is Windows 7)
// Note: According to ACPI spec, _OSI("Windows") must also return true
//  Also, it should return true for all previous versions of Windows.
// In config ACPI, OSID to XSID
// Find:     4F534944
// Replace:  58534944
//
// In config ACPI, OSIF to XSIF
// Find:     4F534946
// Replace:  58534946
//
// In config ACPI, _OSI to XOSI
// Find:     5F4F5349
// Replace:  584F5349
//
// Search _OSI......
//
DefinitionBlock ("", "SSDT", 2, "HACK", "XOSI", 0x00000000)
{
    Method (XOSI, 1, NotSerialized)
    {
        // Based off of https://docs.microsoft.com/en-us/windows-hardware/drivers/acpi/winacpi-osi
        // Add OSes from the above list as needed, most only check up to Windows 2015
        // but check what your DSDT looks for        
        Local0 = Package ()
            {
               //"Windows 2001", 
               //"Windows 2001.1", 
               //"Windows 2001 SP1", 
               // "Windows 2001 SP2", 
               //"Windows 2001 SP3", 
               //"Windows 2006", 
               //"Windows 2006 SP1",                 
               //"Windows 2009"  //  = win7, Win Server 2008 R2
               //"Windows 2012"  //  = Win8, Win Server 2012
               //"Windows 2013"  //  = win8.1
               "Windows 2015"  //  = Win10
               //"Windows 2016"  //  = Win10 version 1607
               //"Windows 2017"  //  = Win10 version 1703
               //"Windows 2017.2"//  = Win10 version 1709
               //"Windows 2018.2"//  = Win10 version 1809
               //"Windows 2019"  //  = Win10 version 1903
               //"Windows 2020"  //  = Win10 version 2004
               //"Windows 2021"  //  = Win11    
               //"Windows 2022", //. = Win11, version 22H2
               //"Windows 2023", //. = Win11, version 23H2
               //"Microsoft Windows NT", 
               //"Microsoft Windows", 
               //"Microsoft WindowsME: Millennium Edition"                         
            }
        If (_OSI ("Darwin"))
        {
            Return ((Ones != Match (Local0, MEQ, Arg0, MTR, Zero, Zero)))
        }
        Else
        {
            Return (_OSI (Arg0))
        }
    }
}
//EOF
