// Inject Fake EC device

DefinitionBlock("", "SSDT", 2, "hack", "_EC", 0)
{
    Device(_SB.EC)
    {
        Name(_HID, "EC000000")
		Method (_STA, 0, NotSerialized)
		{
			If (_OSI ("Darwin"))
			{
				Return (0x0F)
			}
			Else
			{
				Return (Zero)
			}
		}
    }
}
