// Inject Fake EC device

DefinitionBlock("", "SSDT", 2, "hack", "_EC", 0)
{
    Device(_SB.EC)
    {
        Name(_HID, "EC000000")
    }
}
