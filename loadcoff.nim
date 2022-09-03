import winim

import std/[
  strformat,
  strutils,
  bitops
]

import lib/[
  ptrmath, 
  structs,
  debug
]

let fileBuf = cast[seq[byte]](readFile("main.o"))
let fileHeader = cast[ptr FileHeader](unsafeAddr fileBuf[0])

let sectionArray = cast[ptr SectionHeader](
  (unsafeAddr fileBuf[0]) + 
  cast[int](fileHeader.SizeOfOptionalHeader) + 
  sizeof(FileHeader)
)

let symbolArray = cast[ptr SymbolTableEntry](
  (unsafeAddr fileBuf[0]) +
  cast[int](fileHeader.PointerToSymbolTable)
)

let symVals: ptr char = cast[ptr char](
  symbolArray + 
  cast[int](fileHeader.NumberOfSymbols)
)

var sections: seq[tuple[
  name: string, header: ptr SectionHeader, number: int
]]

var sectionMapping: array[25, LPVOID]
var functionMapping: LPVOID = VirtualAlloc(
  NULL, 
  2048, 
  bitor(MEM_COMMIT, MEM_RESERVE, MEM_TOP_DOWN), 
  PAGE_EXECUTE_READWRITE
)
var fmCount = 0

var totalSize: uint64 = 0
for i in 0..(cast[int](fileHeader.NumberOfSections) - 1):
  let sectionHeader: ptr SectionHeader = (sectionArray + i)
  let sectionName = $(unsafeAddr sectionHeader.Name[0])

  when defined(debug):
    echo &"Found {sectionName} @ offset {totalSize}:"
    printSectionHeader(sectionHeader)

    echo &"\tAllocating {sectionHeader.SizeOfRawData} bytes"

  sectionMapping[i] = VirtualAlloc(
    NULL, 
    cast[SIZE_T](sectionHeader.SizeOfRawData), 
    bitor(MEM_COMMIT, MEM_RESERVE, MEM_TOP_DOWN),
    PAGE_EXECUTE_READWRITE
  )

  if sectionMapping[i] != NULL: 
    copyMem(
      sectionMapping[i],
      (unsafeAddr fileBuf[0]) + cast[int](sectionHeader.PointerToRawData),
      sectionHeader.SizeOfRawData
    )
  else: 
    when defined(debug): echo "\tFailed to allocate"

  sections.add (name: sectionName, header: sectionHeader, number: i)
  totalSize += sectionHeader.SizeOfRawData

for section in sections:
  when defined(debug): echo &"Relocations for section: {section.name}"

  let relocationArray: ptr RelocationTableEntry = cast[ptr RelocationTableEntry](
    (unsafeAddr fileBuf[0]) + 
    cast[int](section.header.PointerToRelocations)
  )
  
  for i in 0..(cast[int](section.header.NumberOfRelocations) - 1):
    let relocation = relocationArray[i]
    let symbolEntry: SymbolTableEntry = symbolArray[cast[int](relocation.SymbolTableIndex)]   
    let symbolPtr = symbolEntry.First.value[1]

    when defined(debug):
      echo &"Virtual Address: 0x{toHex(relocation.VirtualAddress)} (SYMBOL: {relocation.SymbolTableIndex}; Type: 0x{toHex(relocation.Type)})"
      echo &"\tSymPtr: 0x{toHex symbolPtr}"

    let sectionIndex = section.number
    
    let patchAddress = cast[ptr byte](
      cast[int](sectionMapping[sectionIndex]) + 
      cast[int](relocation.VirtualAddress)
    )

    if cast[int](symbolEntry.First.Name[0]) != 0:
      
      when defined(debug): 
        let symname = $(unsafeAddr symbolEntry.First.Name[0])
        echo &"\tSymName: {symname}"

      if relocation.Type == IMAGE_REL_AMD64_ADDR64:
        var offsetVal: uint64
        copyMem(
          addr offsetVal, 
          patchAddress, 
          sizeof(uint64)
        )

        when defined(debug): echo &"\t  OffsetVal:    0x{toHex(offsetVal)}"

        offsetVal = cast[uint64](sectionMapping[sectionIndex]) + offsetVal
        
        copyMem(
          patchAddress,
          addr offsetVal,
          sizeof(uint64)
        )
        when defined(debug): echo &"\t  NewOffsetVal: 0x{toHex(offsetVal)}"

      elif relocation.Type == IMAGE_REL_AMD64_ADDR32NB:
        var offsetVal: int32
        copyMem(
          addr offsetVal, 
          patchAddress,
          sizeof(int32)
        )
        var refSection = cast[int32](sectionMapping[symbolEntry.SectionNumber - 1]) + offsetVal
        var endOfReloc = cast[int32](patchAddress) + 4
        if endOfReloc - refSection > 0xffffffff:
          echo "- error: alloc > 4 gigs away, exitting"
          quit(1)

        when defined(debug):
          echo &"\t  OffsetVal:  0x{toHex(offsetVal)}"
          echo &"\t  RefSection: 0x{toHex(refSection)}"
          echo &"\t  RelocEnd:   0x{toHex(endOfReloc)}"
        offsetVal = refSection - endOfReloc 
        
        copyMem(
          patchAddress,
          addr offsetVal, 
          sizeof(uint32)
        )

        when defined(debug): echo &"\t  OffsetVal:  0x{toHex(offsetVal)}"
      elif relocation.Type == IMAGE_REL_AMD64_REL32:
        var offsetVal: int32
        copyMem(addr offsetVal, patchAddress, sizeof(int32))
        when defined(debug): echo &"\t  OffsetVal:  0x{toHex(offsetVal)}"
        offsetVal += cast[int32](sectionMapping[symbolEntry.SectionNumber - 1]) - (cast[int32](patchAddress) + 4)
        copyMem(patchAddress, addr offsetVal, sizeof(int32))
        when defined(debug): echo &"\t  OffsetVal:  0x{toHex(offsetVal)}"
      continue

    let symbolValue = $(unsafeAddr (symVals + cast[int](symbolPtr))[0])
    
    when defined(debug):
      echo &"\tSymVal: {symbolValue}"
      echo &"\tSectionNumber: {symbolEntry.SectionNumber}"
    
    if symbolValue.startsWith("__imp_"):
      let library = symbolValue.replace("__imp_", "").split("$")[0]
      let funcName = symbolValue.replace("__imp_", "").split("$")[1]
      
      let llHandle = LoadLibraryA(library)
      let funcAddress = GetProcAddress(llHandle, funcName)
      if funcAddress == NULL:
        echo "- error couldnt process symbol exitting"
        break

      when defined(debug):
        echo &"\t  !!!!! Found external symbol !!!!!"
        echo &"\t  - Library:  {library}"
        echo &"\t  - FuncName: {funcName}"
        echo &"\t  => address: 0x{toHex(cast[int](funcAddress))}"

      if relocation.Type == IMAGE_REL_AMD64_REL32:
        if cast[int](functionMapping) + (fmCount * 8) - (cast[int](patchAddress)) > 0xfffffff:
          echo "- error relocation 4 gigs away"
          break
      
      copyMem(
        cast[ptr byte](cast[int](functionMapping) + (fmCount * 8)),
        unsafeAddr funcAddress,
        sizeof(uint64)
      )

      let offsetVal = (
        cast[int32](functionMapping) + 
        cast[int32](fmCount * 8) - 
        cast[int32](patchAddress + 4)
      )

      copyMem(
        patchAddress,
        unsafeAddr offsetVal,
        sizeof(uint32)
      )

      inc fmCount


for i in 0..(cast[int](fileHeader.NumberOfSymbols) - 1):
  let symbol = symbolArray[i]
  let symbolName = $(unsafeAddr symbol.First.Name[0])
  if symbolName == "go":
    let fPtr = cast[int](sectionMapping[symbol.SectionNumber - 1]) + cast[int](symbol.Value)
    cast[COFFEntry](fPtr)(NULL, 0)
    break

for allocated in sectionMapping:
  VirtualFree(allocated, 0, MEM_RELEASE)
VirtualFree(functionMapping, 0, MEM_RELEASE)
