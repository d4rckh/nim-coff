
# The bycopy pragma can be applied to an object or tuple type and instructs the compiler to pass the type by value to procs
# * means global type
# Some structs here should be exist in winim/lean but anyway, maybe someone needs such thing . Oi!

type COFFEntry* = proc(args:ptr byte, argssize: uint32) {.stdcall.}

type
    #[
    typedef struct {
	    UINT16 Machine;
	    UINT16 NumberOfSections;
	    UINT32 TimeDateStamp;
	    UINT32 PointerToSymbolTable;
	    UINT32 NumberOfSymbols;
	    UINT16 SizeOfOptionalHeader;
	    UINT16 Characteristics;
        } FileHeader;
    ]#    
    FileHeader* {.bycopy,packed.} = object
        Machine*: uint16
        NumberOfSections*: uint16
        TimeDateStamp*: uint32
        PointerToSymbolTable*: uint32
        NumberOfSymbols*: uint32
        SizeOfOptionalHeader*: uint16
        Characteristics*: uint16

    #[
        typedef struct {
	        char Name[8];					//8 bytes long null-terminated string
	        UINT32 VirtualSize;				//total size of section when loaded into memory, 0 for COFF, might be different because of padding
	        UINT32 VirtualAddress;			//address of the first byte of the section before relocations are applied, should be set to 0
	        UINT32 SizeOfRawData;			//The size of the section for COFF files
	        UINT32 PointerToRawData;		//Pointer to the beginning of the section for COFF
	        UINT32 PointerToRelocations;	//File pointer to the beginning of relocation entries
	        UINT32 PointerToLinenumbers;	//The file pointer to the beginning of line-number entries for the section. T
	        UINT16 NumberOfRelocations;		//The number of relocation entries for the section. This is set to zero for executable images. 
	        UINT16 NumberOfLinenumbers;		//The number of line-number entries for the section. This value should be zero for an image because COFF debugging information is deprecated. 
	        UINT32 Characteristics;			//The flags that describe the characteristics of the section
            } SectionHeader;
    ]#
    SectionHeader* {.bycopy,packed.} = object
        Name*: array[8,char]
        VirtualSize*: uint32
        VirtualAddress*: uint32
        SizeOfRawData*: uint32
        PointerToRawData*: uint32
        PointerToRelocations*: uint32
        PointerToLinenumbers*: uint32
        NumberOfRelocations*: uint16
        NumberOfLinenumbers*: uint16
        Characteristics*: uint32

    #[
        typedef struct {
	        union {
		        char Name[8];					//8 bytes, name of the symbol, represented as a union of 3 structs
		        UINT32	value[2];				//TODO: what does this represent?!
	        } first;
	        UINT32 Value;					//meaning depends on the section number and storage class
	        UINT16 SectionNumber;			//signed int, some values have predefined meaning
	        UINT16 Type;					//
	        UINT8 StorageClass;				//
	        UINT8 NumberOfAuxSymbols;
            } SymbolTableEntry;
    ]#

    UnionFirst* {.final,union,pure.} = object
        Name*: array[8,char]
        value*: array[2,uint32]
    
   

    SymbolTableEntry* {.bycopy, packed.} = object
        First*: UnionFirst
        Value*: uint32
        SectionNumber*: uint16
        Type*: uint16
        StorageClass*: uint8
        NumberOfAuxSymbols*: uint8

    #[
        typedef struct {
	        UINT32 VirtualAddress;
	        UINT32 SymbolTableIndex;
	        UINT16 Type;
        } RelocationTableEntry;
    ]#

    RelocationTableEntry* {.bycopy, packed.} = object
        VirtualAddress*: uint32
        SymbolTableIndex*: uint32
        Type*: uint16
    
    SectionInfo* {.bycopy.} = object
        Name*: string
        SectionOffset*: uint64
        SectionHeaderPtr*: ptr SectionHeader
