import std/[
  strformat,
  strutils
]

import structs

proc printSectionHeader*(sectionHeader: ptr SectionHeader) =
  when defined(debug):
    echo &"\tVirtual Size: {sectionHeader.VirtualSize}"
    echo &"\tVirtual Address: 0x{toHex(sectionHeader.VirtualAddress)}"
    echo &"\tRaw Data Size: {sectionHeader.SizeOfRawData}"
    echo &"\tRaw Data Ptr: 0x{toHex(sectionHeader.PointerToRawData)}"
    echo &"\tRelocations Ptr: 0x{toHex(sectionHeader.PointerToRelocations)}"
    echo &"\tLine numbers Ptr: {sectionHeader.PointerToLinenumbers}"
    echo &"\tRelocations Count: {sectionHeader.NumberOfRelocations}"
    echo &"\tLine Count: {sectionHeader.NumberOfLinenumbers}"
    echo &"\tCharacteristics: {sectionHeader.Characteristics}"
  else: discard