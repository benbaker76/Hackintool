#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <sys/types.h>
#include <CoreFoundation/CoreFoundation.h>            // (CFDictionary, ...)
#include <IOKit/IOCFSerialize.h>                      // (IOCFSerialize, ...)
#include <IOKit/IOKitLib.h>							  // (IOMasterPort, ...)
//#include "utils.h"
#include "efidevp.h"

/*
 * Get parameter in a pair of parentheses follow the given node name.
 * For example, given the "Pci(0,1)" and NodeName "Pci", it returns "0,1".
 */
char *GetParamByNodeName (CHAR8 *Str, CHAR8 *NodeName)
{
	CHAR8  *ParamStr;
	CHAR8  *StrPointer;
	UINT32 NodeNameLength;
	UINT32 ParameterLength;
	
	// Check whether the node name matchs
	NodeNameLength = (UINT32)strlen (NodeName);
	if (strncasecmp(Str, NodeName, NodeNameLength) != 0)
	{
		return NULL;
	}
	
	ParamStr = Str + NodeNameLength;
	if (!IS_LEFT_PARENTH (*ParamStr))
	{
		return NULL;
	}
	
	// Skip the found '(' and find first occurrence of ')'
	ParamStr++;
	ParameterLength = 0;
	StrPointer = ParamStr;
	
	while (!IS_NULL (*StrPointer))
	{
		if (IS_RIGHT_PARENTH (*StrPointer))
		{
			break;
		}
		StrPointer++;
		ParameterLength++;
	}
	
	if (IS_NULL (*StrPointer))
	{
		// ')' not found
		return NULL;
	}
	
	ParamStr = MallocCopy ((ParameterLength + 1), (ParameterLength + 1), ParamStr);
	if (ParamStr == NULL)
	{
		return NULL;
	}
	// Terminate the parameter string
	ParamStr[ParameterLength] = '\0';
	
	return ParamStr;
}

/* Get current sub-string from a string list, before return
 * the list header is moved to next sub-string. The sub-string is separated
 * by the specified character. For example, the separator is ',', the string
 * list is "2,0,3", it returns "2", the remain list move to "0,3"
 */
CHAR8 *SplitStr (CHAR8 **List, CHAR8 Separator)
{
	char  *Str;
	char  *ReturnStr;
	
	Str = *List;
	ReturnStr = Str;
	
	if (IS_NULL (*Str))
	{
		return ReturnStr;
	}
	
	// Find first occurrence of the separator
	while (!IS_NULL (*Str))
	{
		if (*Str == Separator)
		{
			break;
		}
		Str++;
	}
	
	if (*Str == Separator)
	{
		// Find a sub-string, terminate it
		*Str = '\0';
		Str++;
	}
	
	// Move to next sub-string
	*List = Str;
	
	return ReturnStr;
}

CHAR8 *GetNextParamStr (CHAR8 **List)
{
	// The separator is comma
	return SplitStr (List, ',');
}

// Get one device node from entire device path text.
CHAR8 *GetNextDeviceNodeStr (CHAR8 **DevicePath, BOOLEAN *IsInstanceEnd)
{
	CHAR8  *Str;
	CHAR8  *ReturnStr;
	UINT32  ParenthesesStack;
	
	Str = *DevicePath;
	if (IS_NULL (*Str))
	{
		return NULL;
	}
	
	// Skip the leading '/', '(', ')' and ','
	while (!IS_NULL (*Str))
	{
		if (!IS_SLASH (*Str) && !IS_COMMA (*Str) && !IS_LEFT_PARENTH (*Str) && !IS_RIGHT_PARENTH (*Str))
		{
			break;
		}
		Str++;
	}
	
	ReturnStr = Str;
	
	// Scan for the separator of this device node, '/' or ','
	ParenthesesStack = 0;
	while (!IS_NULL (*Str))
	{
		if ((IS_COMMA (*Str) || IS_SLASH (*Str)) && (ParenthesesStack == 0))
		{
			break;
		}
		
		if (IS_LEFT_PARENTH (*Str))
		{
			ParenthesesStack++;
		}
		else if (IS_RIGHT_PARENTH (*Str))
		{
			ParenthesesStack--;
		}
		
		Str++;
	}
	
	if (ParenthesesStack != 0)
	{
		// The '(' doesn't pair with ')', invalid device path text
		return NULL;
	}
	
	if (IS_COMMA (*Str))
	{
		*IsInstanceEnd = 1;
		*Str = '\0';
		Str++;
	}
	else
	{
		*IsInstanceEnd = 0;
		if (!IS_NULL (*Str))
		{
			*Str = '\0';
			Str++;
		}
	}
	
	*DevicePath = Str;
	
	return ReturnStr;
}

/*
 * Function unpacks a device path data structure so that all the nodes of a device path
 * are naturally aligned.
 */
EFI_DEVICE_PATH *UnpackDevicePath (EFI_DEVICE_PATH  *DevPath)
{
	EFI_DEVICE_PATH  *Src;
	EFI_DEVICE_PATH  *Dest;
	EFI_DEVICE_PATH  *NewPath;
	UINT32			Size;
	UINT32			Count;
	
	if (DevPath == NULL)
	{
		return NULL;
	}
	
	// Walk device path and round sizes to valid boundries
	Src   = DevPath;
	Size  = 0;
	for (Count = 0;;Count++)
	{
		if(Count > MAX_DEVICE_PATH_LEN)
		{
			// BugBug: Code to catch bogus device path
			fprintf(stderr, "UnpackDevicePath: Cannot find device path end! Probably a bogus device path\n");
			return NULL;
		}
		Size += DevicePathNodeLength (Src);
		Size += ALIGN_SIZE (Size);
		
		if (IsDevicePathEnd (Src))
		{
			break;
		}
		
		Src = (EFI_DEVICE_PATH *) NextDevicePathNode (Src);
	}
	
	// Allocate space for the unpacked path
	NewPath = (EFI_DEVICE_PATH *)malloc(Size);
	
	if (NewPath != NULL)
	{
		assert(((UINT32) NewPath) % MIN_ALIGNMENT_SIZE == 0);
		
		memset(NewPath, 0, Size);
		
		// Copy each node
		Src   = DevPath;
		Dest  = NewPath;
		for (;;)
		{
			Size = DevicePathNodeLength (Src);
			memcpy(Dest, Src, Size);
			Size += ALIGN_SIZE (Size);
			SetDevicePathNodeLength (Dest, Size);
			Dest->Type |= EFI_DP_TYPE_UNPACKED;
			Dest = (EFI_DEVICE_PATH *) (((UINT8 *) Dest) + Size);
			
			if (IsDevicePathEnd (Src))
			{
				break;
			}
			
			Src = (EFI_DEVICE_PATH *) NextDevicePathNode (Src);
		}
	}
	
	return NewPath;
}

// Returns the size of the device path, in bytes.
UINT32 DevicePathSize (const EFI_DEVICE_PATH  *DevicePath)
{
	const EFI_DEVICE_PATH *Start;
	UINT32 Count = 0;
	
	if (DevicePath == NULL)
	{
		return 0;
	}
	
	// Search for the end of the device path structure
	Start = (EFI_DEVICE_PATH *) DevicePath;
	for (Count = 0;!IsDevicePathEnd(DevicePath);Count++)
	{
		if(Count > MAX_DEVICE_PATH_LEN)
		{
			// BugBug: Code to catch bogus device path
			fprintf(stderr, "DevicePathSize: Cannot find device path end! Probably a bogus device path\n");
			return 0;
		}
		DevicePath = NextDevicePathNode (DevicePath);
	}
	
	// Compute the size and add back in the size of the end device path structure
	return ((UINT32) DevicePath - (UINT32) Start) + sizeof (EFI_DEVICE_PATH);
}

// Creates a device node
EFI_DEVICE_PATH *CreateDeviceNode (UINT8 NodeType, UINT8 NodeSubType, UINT16 NodeLength)
{
	EFI_DEVICE_PATH *Node;
	
	if (NodeLength < sizeof (EFI_DEVICE_PATH))
	{
		return NULL;
	}
	
	Node = (EFI_DEVICE_PATH *) malloc ((UINT32) NodeLength);
	if (Node != NULL)
	{
		memset(Node, 0, NodeLength);
		Node->Type    = NodeType;
		Node->SubType = NodeSubType;
		SetDevicePathNodeLength (Node, NodeLength);
	}
	
	return Node;
}

// Duplicate a device path structure.
EFI_DEVICE_PATH *DuplicateDevicePath (EFI_DEVICE_PATH *DevicePath)
{
	EFI_DEVICE_PATH *NewDevicePath;
	UINT32 Size;
	
	if (DevicePath == NULL)
	{
		return NULL;
	}
	
	// Compute the size
	Size = DevicePathSize (DevicePath);
	if (Size == 0)
	{
		return NULL;
	}
	
	// Allocate space for duplicate device path
	NewDevicePath = MallocCopy(Size, Size, DevicePath);
	
	return NewDevicePath;
}

//  Function is used to append a Src1 and Src2 together.
EFI_DEVICE_PATH *AppendDevicePath (EFI_DEVICE_PATH *Src1, EFI_DEVICE_PATH *Src2)
{
	UINT32 Size;
	UINT32 Size1;
	UINT32 Size2;
	EFI_DEVICE_PATH  *NewDevicePath;
	EFI_DEVICE_PATH  *SecondDevicePath;
	
	// If there's only 1 path, just duplicate it
	if (!Src1)
	{
		assert(!IsDevicePathUnpacked (Src2));
		return DuplicateDevicePath (Src2);
	}
	
	if (!Src2) {
		assert(!IsDevicePathUnpacked (Src1));
		return DuplicateDevicePath (Src1);
	}
	
	// Allocate space for the combined device path. It only has one end node of
	// length EFI_DEVICE_PATH
	
	Size1         = DevicePathSize (Src1);
	Size2         = DevicePathSize (Src2);
	Size          = Size1 + Size2 - sizeof (EFI_DEVICE_PATH);
	
	NewDevicePath = MallocCopy(Size, Size1, Src1);
	
	if (NewDevicePath != NULL)
	{
		// Over write Src1 EndNode and do the copy
		SecondDevicePath = (EFI_DEVICE_PATH *) ((CHAR8 *) NewDevicePath + (Size1 - sizeof (EFI_DEVICE_PATH)));
		memcpy(SecondDevicePath, Src2, Size2);
	}
	
	return NewDevicePath;
}


// Function is used to append a device path node to the end of another device path.
EFI_DEVICE_PATH *AppendDevicePathNode (EFI_DEVICE_PATH  *Src1, EFI_DEVICE_PATH  *Node)
{
	EFI_DEVICE_PATH  *Temp;
	EFI_DEVICE_PATH  *NextNode;
	EFI_DEVICE_PATH  *NewDevicePath;
	UINT32			NodeLength;
	
	// Build a Node that has a terminator on it
	NodeLength  = DevicePathNodeLength (Node);
	
	Temp = MallocCopy(NodeLength + sizeof (EFI_DEVICE_PATH), NodeLength, Node);
	if (Temp == NULL)
	{
		return NULL;
	}
	
	// Add and end device path node to convert Node to device path
	NextNode = NextDevicePathNode (Temp);
	SetDevicePathEndNode (NextNode);
	
	// Append device paths
	NewDevicePath = AppendDevicePath (Src1, Temp);
	free(Temp);
	return NewDevicePath;
}

// Function is used to insert a device path node to the beginning of another device path.
EFI_DEVICE_PATH *InsertDevicePathNode (EFI_DEVICE_PATH  *Src1, EFI_DEVICE_PATH  *Node)
{
	EFI_DEVICE_PATH  *Temp;
	EFI_DEVICE_PATH  *NextNode;
	EFI_DEVICE_PATH  *NewDevicePath;
	UINT32			NodeLength;
	
	// Build a Node that has a terminator on it
	NodeLength  = DevicePathNodeLength (Node);
	
	Temp = MallocCopy(NodeLength + sizeof (EFI_DEVICE_PATH), NodeLength, Node);
	if (Temp == NULL)
	{
		return NULL;
	}
	
	// Add and end device path node to convert Node to device path
	NextNode = NextDevicePathNode (Temp);
	SetDevicePathEndNode (NextNode);
	
	// Append device paths
	NewDevicePath = AppendDevicePath (Temp, Src1);
	free(Temp);
	return NewDevicePath;
}

void EisaIdToText (UINT32 EisaId, CHAR8 *Text)
{
	CHAR8 PnpIdStr[17];
	
	//SPrint ("%X", 0x0a03) => "0000000000000A03"
	snprintf(PnpIdStr, 17, "%X", EisaId >> 16);
	snprintf(Text,0,"%c%c%c%s",'@' + ((EisaId >> 10) & 0x1f),'@' + ((EisaId >>  5) & 0x1f),'@' + ((EisaId >>  0) & 0x1f), PnpIdStr + (16 - 4));
}

void EisaIdFromText (CHAR8 *Text, UINT32 *EisaId)
{
	UINT32 PnpId;
	
	PnpId = Xtoi (Text + 3, NULL);
	*EisaId = (((Text[0] - '@') & 0x1f) << 10) +
	(((Text[1] - '@') & 0x1f) << 5) +
	((Text[2] - '@') & 0x1f) +
	(UINT32) (PnpId << 16);
}

void DevPathToTextPci (CHAR8  *Str, void  *DevPath, BOOLEAN DisplayOnly, BOOLEAN AllowShortcuts)
{
	PCI_DEVICE_PATH *Pci;
	
	Pci = DevPath;
	CatPrintf(Str, "Pci(0x%x,0x%x)", Pci->Device, Pci->Function);
}

EFI_DEVICE_PATH * DevPathFromTextPci (CHAR8 *TextDeviceNode)
{
	CHAR8			*FunctionStr;
	CHAR8			*DeviceStr;
	PCI_DEVICE_PATH *Pci;
	
	DeviceStr   = GetNextParamStr (&TextDeviceNode);
	FunctionStr = GetNextParamStr (&TextDeviceNode);
	
	Pci         = (PCI_DEVICE_PATH *) CreateDeviceNode (
														HARDWARE_DEVICE_PATH,
														HW_PCI_DP,
														sizeof (PCI_DEVICE_PATH)
														);
	
	Pci->Function = (UINT8) Strtoi (FunctionStr, NULL);
	Pci->Device   = (UINT8) Strtoi (DeviceStr, NULL);
	
	return (EFI_DEVICE_PATH *) Pci;
}

EFI_DEVICE_PATH * DevPathFromTextPciAdr (CHAR8 *TextDeviceNode)
{
	CHAR8			*AdrStr;
	PCI_DEVICE_PATH *Pci;
	
	AdrStr   = GetNextParamStr (&TextDeviceNode);
	
	Pci         = (PCI_DEVICE_PATH *) CreateDeviceNode (
														HARDWARE_DEVICE_PATH,
														HW_PCI_DP,
														sizeof (PCI_DEVICE_PATH)
														);
	
	Pci->Function = (UINT8) (Strtoi (AdrStr, NULL) & 0xFF);
	Pci->Device   = (UINT8) ((Strtoi (AdrStr, NULL) >> 16) & 0xFF);
	
	return (EFI_DEVICE_PATH *) Pci;
}

void DevPathToTextAcpi (CHAR8 *Str, void *DevPath, BOOLEAN DisplayOnly, BOOLEAN AllowShortcuts)
{
	ACPI_HID_DEVICE_PATH  *Acpi;
	
	Acpi = DevPath;
	if ((Acpi->HID & PNP_EISA_ID_MASK) == PNP_EISA_ID_CONST)
	{
		switch (EISA_ID_TO_NUM (Acpi->HID))
		{
			case 0x0a03:
				CatPrintf(Str, "PciRoot(0x%x)", Acpi->UID);
				break;
			default:
				CatPrintf(Str, "Acpi(PNP%04x,0x%x)", EISA_ID_TO_NUM (Acpi->HID), Acpi->UID);
				break;
		}
	}
	else
	{
		CatPrintf(Str, "Acpi(0x%08x,0x%x)", Acpi->HID, Acpi->UID);
	}
}

EFI_DEVICE_PATH *DevPathFromTextAcpi (CHAR8 *TextDeviceNode)
{
	CHAR8 *HIDStr;
	CHAR8 *UIDStr;
	ACPI_HID_DEVICE_PATH  *Acpi;
	
	HIDStr = GetNextParamStr (&TextDeviceNode);
	UIDStr = GetNextParamStr (&TextDeviceNode);
	Acpi   = (ACPI_HID_DEVICE_PATH *) CreateDeviceNode (
														ACPI_DEVICE_PATH,
														ACPI_DP,
														sizeof (ACPI_HID_DEVICE_PATH)
														);
	
	EisaIdFromText (HIDStr, &Acpi->HID);
	Acpi->UID = (UINT32) Strtoi (UIDStr, NULL);
	
	return (EFI_DEVICE_PATH *) Acpi;
}

void MediaDevPathToTextHDD (CHAR8 *Str, void *DevPath)
{
	HARDDRIVE_DEVICE_PATH  *Hdd;
	
	Hdd = DevPath;
	
	CatPrintf(Str, "%04X-%02X-%02X-%1X%1X-%1X%1X%1X%1X%1X%1X", Hdd->UUid.Data1, Hdd->UUid.Data2, Hdd->UUid.Data3, Hdd->UUid.Data4[0], Hdd->UUid.Data4[1], Hdd->UUid.Data5[0], Hdd->UUid.Data5[1], Hdd->UUid.Data5[2], Hdd->UUid.Data5[3], Hdd->UUid.Data5[4], Hdd->UUid.Data5[5]);
}

EFI_DEVICE_PATH *ConvertFromTextAcpi (CHAR8 *TextDeviceNode, UINT32 PnPId)
{
	CHAR8 *UIDStr;
	ACPI_HID_DEVICE_PATH  *Acpi;
	
	UIDStr = GetNextParamStr (&TextDeviceNode);
	Acpi   = (ACPI_HID_DEVICE_PATH *) CreateDeviceNode (
														ACPI_DEVICE_PATH,
														ACPI_DP,
														sizeof (ACPI_HID_DEVICE_PATH)
														);
	
	Acpi->HID = EFI_PNP_ID (PnPId);
	Acpi->UID = (UINT32) Strtoi (UIDStr, NULL);
	
	return (EFI_DEVICE_PATH *) Acpi;
}

EFI_DEVICE_PATH *DevPathFromTextPciRoot (CHAR8 *TextDeviceNode)
{
	return ConvertFromTextAcpi (TextDeviceNode, 0x0a03);
}

void DevPathToTextEndInstance (CHAR8 *Str, void *DevPath, BOOLEAN DisplayOnly, BOOLEAN AllowShortcuts)
{
	CatPrintf(Str, ",");
}

void DevPathToTextNodeUnknown (CHAR8 *Str, void *DevPath, BOOLEAN DisplayOnly, BOOLEAN AllowShortcuts)
{
	CatPrintf(Str, "?");
}

DEVICE_PATH_TO_TEXT_TABLE DevPathToTextTable[] =
{
	HARDWARE_DEVICE_PATH,
	HW_PCI_DP,
	DevPathToTextPci,
	ACPI_DEVICE_PATH,
	ACPI_DP,
	DevPathToTextAcpi,
	END_DEVICE_PATH_TYPE,
	END_INSTANCE_DEVICE_PATH_SUBTYPE,
	DevPathToTextEndInstance,
	0,
	0,
	NULL
};

DEVICE_PATH_FROM_TEXT_TABLE DevPathFromTextTable[] = {
	"Pci",
	DevPathFromTextPci,
	"PciAdr",
	DevPathFromTextPciAdr,
	"Acpi",
	DevPathFromTextAcpi,
	"PciRoot",
	DevPathFromTextPciRoot,
	NULL,
	NULL
};

// Convert text to the binary representation of a device node.
EFI_DEVICE_PATH *ConvertTextToDeviceNode (const CHAR8 *TextDeviceNode)
{
	EFI_DEVICE_PATH	*(*DumpNode) (CHAR8 *);
	CHAR8				*ParamStr;
	EFI_DEVICE_PATH	*DeviceNode;
	CHAR8				*DeviceNodeStr;
	UINT32			Index;
	
	if ((TextDeviceNode == NULL) || (IS_NULL (*TextDeviceNode)))
	{
		return NULL;
	}
	
	ParamStr      = NULL;
	DumpNode      = NULL;
	DeviceNodeStr = strdup(TextDeviceNode);
	
	for (Index = 0; DevPathFromTextTable[Index].Function; Index++)
	{
		ParamStr = GetParamByNodeName (DeviceNodeStr, DevPathFromTextTable[Index].DevicePathNodeText);
		if (ParamStr != NULL)
		{
			DumpNode = DevPathFromTextTable[Index].Function;
			break;
		}
	}
	
	if (DumpNode == NULL)
	{
		fprintf(stderr, "Unknown device node '%s'! Check syntax!\n",DeviceNodeStr);
		return NULL;
	}
	else
	{
		DeviceNode = DumpNode (ParamStr);
		free(ParamStr);
	}
	
	free(DeviceNodeStr);
	
	return DeviceNode;
}

// Convert text to the binary representation of a device path.
EFI_DEVICE_PATH *ConvertTextToDevicePath (const CHAR8 *TextDevicePath)
{
	EFI_DEVICE_PATH	*(*DumpNode) (CHAR8 *);
	CHAR8				*ParamStr;
	EFI_DEVICE_PATH	*DeviceNode;
	UINT32			Index;
	EFI_DEVICE_PATH	*NewDevicePath;
	CHAR8				*DevicePathStr;
	CHAR8				*Str;
	CHAR8				*DeviceNodeStr;
	BOOLEAN			IsInstanceEnd;
	EFI_DEVICE_PATH	*DevicePath;
	
	if ((TextDevicePath == NULL) || (IS_NULL (*TextDevicePath)))
	{
		return NULL;
	}
	
	DevicePath = (EFI_DEVICE_PATH *)malloc(END_DEVICE_PATH_LENGTH);
	SetDevicePathEndNode (DevicePath);
	
	ParamStr            = NULL;
	DeviceNodeStr       = NULL;
	DevicePathStr       = strdup(TextDevicePath);
	
	Str                 = DevicePathStr;
	while ((DeviceNodeStr = GetNextDeviceNodeStr (&Str, &IsInstanceEnd)) != NULL)
	{
		DumpNode = NULL;
		for (Index = 0; DevPathFromTextTable[Index].Function; Index++)
		{
			ParamStr = GetParamByNodeName (DeviceNodeStr, DevPathFromTextTable[Index].DevicePathNodeText);
			if (ParamStr != NULL)
			{
				DumpNode = DevPathFromTextTable[Index].Function;
				break;
			}
		}
		
		if (DumpNode == NULL)
		{
			fprintf(stderr, "Unknown device node '%s'! Check syntax!\n",DeviceNodeStr);
			free(DevicePath);
			return NULL;
		}
		else
		{
			DeviceNode = DumpNode (ParamStr);
			free(ParamStr);
		}
		
		NewDevicePath = AppendDevicePathNode (DevicePath, DeviceNode);
		free(DevicePath);
		free(DeviceNode);
		DevicePath = NewDevicePath;
		
		if (IsInstanceEnd)
		{
			DeviceNode = (EFI_DEVICE_PATH*) malloc(END_DEVICE_PATH_LENGTH);
			SetDevicePathEndNode(DeviceNode);
			
			NewDevicePath = AppendDevicePathNode (DevicePath, DeviceNode);
			free(DevicePath);
			free(DeviceNode);
			DevicePath = NewDevicePath;
		}
	}
	
	free(DevicePathStr);
	return DevicePath;
}

// Convert a device node to its text representation.
CHAR8 *ConvertDeviceNodeToText (const EFI_DEVICE_PATH *DeviceNode, BOOLEAN DisplayOnly, BOOLEAN AllowShortcuts)
{
	CHAR8	*Str;
	UINT32	Index;
	UINT32	NewSize;
	
	void (*DumpNode)(CHAR8 *, void *, BOOLEAN, BOOLEAN);
	
	if (DeviceNode == NULL)
	{
		return NULL;
	}
	
	Str = (CHAR8 *)calloc(MAX_PATH_LEN, sizeof(CHAR8));
	
	DumpNode = NULL;
	for (Index = 0; DevPathToTextTable[Index].Function != NULL; Index++)
	{
		if (DevicePathType (DeviceNode) == DevPathToTextTable[Index].Type &&
			DevicePathSubType (DeviceNode) == DevPathToTextTable[Index].SubType)
		{
			DumpNode = DevPathToTextTable[Index].Function;
			break;
		}
	}
	
	if (DumpNode == NULL)
	{
		DumpNode = DevPathToTextNodeUnknown;
	}
	
	DumpNode (Str, (void *) DeviceNode, DisplayOnly, AllowShortcuts);
	
	// Shrink pool used for string allocation
	NewSize = (UINT32)(strlen(Str) + 1);
	Str = realloc(Str, NewSize);
	assert(Str != NULL);
	Str[strlen(Str)] = 0;
	return Str;
}

// Convert a device path to its text representation.
CHAR8 *ConvertDevicePathToText (const EFI_DEVICE_PATH *DevicePath, BOOLEAN DisplayOnly, BOOLEAN AllowShortcuts)
{
	CHAR8				*Str;
	EFI_DEVICE_PATH		*DevPathNode;
	EFI_DEVICE_PATH		*UnpackDevPath;
	UINT32				Index;
	UINT32				NewSize;
	void (*DumpNode) (CHAR8 *, void *, BOOLEAN, BOOLEAN);
	
	if (DevicePath == NULL)
	{
		return NULL;
	}
	
	Str = (CHAR8 *)calloc(MAX_PATH_LEN, sizeof(CHAR8));
	
	// Unpacked the device path
	UnpackDevPath = UnpackDevicePath ((EFI_DEVICE_PATH *) DevicePath);
	assert(UnpackDevPath != NULL);
	
	// Process each device path node
	DevPathNode = UnpackDevPath;
	while (!IsDevicePathEnd (DevPathNode))
	{
		// Find the handler to dump this device path node
		DumpNode = NULL;
		for (Index = 0; DevPathToTextTable[Index].Function; Index += 1)
		{
			if (DevicePathType (DevPathNode) == DevPathToTextTable[Index].Type &&
				DevicePathSubType (DevPathNode) == DevPathToTextTable[Index].SubType)
			{
				DumpNode = DevPathToTextTable[Index].Function;
				break;
			}
		}
		// If not found, use a generic function
		if (!DumpNode)
		{
			DumpNode = DevPathToTextNodeUnknown;
		}
		
		//  Put a path seperator in if needed
		if (strlen(Str) && DumpNode != DevPathToTextEndInstance)
		{
			if (*(Str + strlen(Str) - 1) != ',')
			{
				CatPrintf(Str, "/");
			}
		}
		// Print this node of the device path
		DumpNode (Str, DevPathNode, DisplayOnly, AllowShortcuts);
		
		// Next device path node
		DevPathNode = NextDevicePathNode (DevPathNode);
	}
	
	// Shrink pool used for string allocation
	free(UnpackDevPath);
	NewSize = (UINT32)(strlen(Str) + 1);
	Str = realloc(Str, NewSize);
	assert(Str != NULL);
	Str[strlen(Str)] = 0;
	return Str;
}

// Convert a HDD device path to its text representation.
CHAR8 *ConvertHDDDevicePathToText (const EFI_DEVICE_PATH *DevicePath)
{
	CHAR8				*Str;
	EFI_DEVICE_PATH		*DevPathNode;
	EFI_DEVICE_PATH		*UnpackDevPath;
	UINT32				NewSize;
	
	if (DevicePath == NULL)
	{
		return NULL;
	}
	
	Str = (CHAR8 *)calloc(MAX_PATH_LEN, sizeof(CHAR8));
	
	// Unpacked the device path
	UnpackDevPath = UnpackDevicePath ((EFI_DEVICE_PATH *) DevicePath);
	assert(UnpackDevPath != NULL);
	
	// Process each device path node
	DevPathNode = UnpackDevPath;
	while (!IsDevicePathEnd (DevPathNode))
	{
		if (DevicePathType (DevPathNode) != MEDIA_DEVICE_PATH || DevicePathSubType (DevPathNode) != MEDIA_HARDDRIVE_DP)
		{
			DevPathNode = NextDevicePathNode (DevPathNode);
			continue;
		}
		
		// Print this node of the device path
		MediaDevPathToTextHDD (Str, DevPathNode);
		
		break;
	}
	
	// Shrink pool used for string allocation
	free(UnpackDevPath);
	NewSize = (UINT32)(strlen(Str) + 1);
	Str = realloc(Str, NewSize);
	assert(Str != NULL);
	Str[strlen(Str)] = 0;
	return Str;
}

io_iterator_t RecursiveFindDevicePath(io_iterator_t iterator, const io_string_t search, const io_name_t plane, EFI_DEVICE_PATH **DevicePath, BOOLEAN *match)
{
	io_registry_entry_t		entry = 0, previous = 0;
	io_string_t				name = {0};
	unsigned int			size = 0;
	CHAR8					*location = NULL;
	io_struct_inband_t		prop_pnp = {0};
	io_struct_inband_t		prop_name = {0};
	io_struct_inband_t		prop_ioname = {0};
	io_struct_inband_t		prop_uid = {0};
	kern_return_t			status = KERN_SUCCESS;
	ACPI_HID_DEVICE_PATH	*Acpi = NULL;
	EFI_DEVICE_PATH			*NewDevicePath = NULL;
	EFI_DEVICE_PATH			*DeviceNode = NULL;
	PCI_DEVICE_PATH			*Pci = NULL;
	CHAR8					*FunctionStr = NULL;
	CHAR8					*DeviceStr = NULL;
	
	while((entry = IOIteratorNext(iterator)) != 0)
	{
		status = IORegistryEntryGetNameInPlane(entry, plane, name);
		assertion(status == KERN_SUCCESS, "can't obtain registry entry name");
		
		size = sizeof(prop_name);
		IORegistryEntryGetProperty(entry, "name", prop_name, &size);
		
		size = sizeof(prop_ioname);
		IORegistryEntryGetProperty(entry, "IOName", prop_ioname, &size);
		
		if (!strcasecmp(prop_name, search) || !strcasecmp(prop_ioname, search) || !strcasecmp(name, search))
		{
			// found match return current entry
			IOObjectRelease((unsigned int)prop_name);
			IOObjectRelease((unsigned int)prop_ioname);
			IOObjectRelease((unsigned int)name);
			*match = true;
			return entry;
		}
		IOObjectRelease((unsigned int)prop_name);
		IOObjectRelease((unsigned int)prop_ioname);
		IOObjectRelease((unsigned int)name);
		
		if(KERN_SUCCESS == IORegistryIteratorEnterEntry(iterator))
		{
			previous = RecursiveFindDevicePath(iterator,search, plane, DevicePath, match);
			IORegistryIteratorExitEntry(iterator);
			
			if(*match)
			{
				if(IOObjectConformsTo(previous,"IOACPIPlatformDevice")) //ACPI node
				{
					//first get compatible pnp
					size = sizeof(prop_pnp);
					if(KERN_SUCCESS != IORegistryEntryGetProperty(previous, "compatible", prop_pnp, &size))
					{
						// get pnp
						size = sizeof(prop_pnp);
						status = IORegistryEntryGetProperty(previous, "name", prop_pnp, &size);
						assertion(status == KERN_SUCCESS, "can't obtain IOACPIPlatformDevice PNP id");
					}
					
					// Create new acpi device node
					Acpi   = (ACPI_HID_DEVICE_PATH *) CreateDeviceNode (
																		ACPI_DEVICE_PATH,
																		ACPI_DP,
																		sizeof (ACPI_HID_DEVICE_PATH)
																		);
					
					// get uid
					size = sizeof(prop_uid);
					if(KERN_SUCCESS == IORegistryEntryGetProperty(previous, "_UID", prop_uid, &size))
					{
						Acpi->UID = (UINT32)Dtoi(prop_uid);
					}
					else
					{
						Acpi->UID = 0;
					}
					
					EisaIdFromText (prop_pnp, &Acpi->HID);
					
					DeviceNode = (EFI_DEVICE_PATH *)Acpi;
					
					IOObjectRelease((unsigned int)prop_pnp);
				}
				else if(IOObjectConformsTo(previous,"IOPCIDevice")) //PCI node
				{
					location = (CHAR8 *)malloc(sizeof(io_string_t));
					status = IORegistryEntryGetLocationInPlane(previous, plane, location);
					assertion(status == KERN_SUCCESS, "can't obtain IOPCIDevice location");
					
					DeviceStr   = GetNextParamStr (&location);
					FunctionStr = GetNextParamStr (&location);
					
					Pci         = (PCI_DEVICE_PATH *) CreateDeviceNode (
																		HARDWARE_DEVICE_PATH,
																		HW_PCI_DP,
																		sizeof (PCI_DEVICE_PATH)
																		);
					
					Pci->Function = (UINT8) Xtoi (FunctionStr, NULL) & 0xff;
					Pci->Device   = (UINT8) Xtoi (DeviceStr, NULL) & 0xff;
					
					DeviceNode = (EFI_DEVICE_PATH *) Pci;
					
					IOObjectRelease((unsigned int)location);
				}
				else
					continue;
				
				if(DeviceNode != NULL)
				{
					// Add node
					NewDevicePath = InsertDevicePathNode(*DevicePath, DeviceNode);
					*DevicePath = NewDevicePath;
				}
				
				return entry;
			}
		}
	}
	
	return 0;
}
