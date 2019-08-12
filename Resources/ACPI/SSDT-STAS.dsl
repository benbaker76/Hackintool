// Fix RTC _STA bug

DefinitionBlock ("", "SSDT", 1, "HACK", "_STAS", 0x00000000)
{
    External (STAS, IntObj)

    Scope (_SB)
    {
        Method (_INI, 0, NotSerialized)
        {
            If (_OSI ("Darwin"))
            {
                STAS = One
            }
        }
    }
}
