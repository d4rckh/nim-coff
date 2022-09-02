import winim

import std/[
  strformat,
  strutils,
  bitops
]

import lib/[
  ptrmath, 
  structs
]

let fileBuf = cast[seq[byte]](readFile("main.o"))

# parse the file header
# its the first thing in the obj file
let fileHeader = cast[ptr FileHeader](unsafeAddr fileBuf[0])

# get a pointer to the array of section info structs
# its located after the file header, and the optional headers 
let sectionArray = cast[ptr SectionHeader](
  (unsafeAddr fileBuf[0]) + 
  cast[int](fileHeader.SizeOfOptionalHeader) + 
  sizeof(FileHeader)
)

# get a pointer to the array of symbol table entries
# its location is given in the file header
var symbolArray = cast[ptr SymbolTableEntry](
  (unsafeAddr fileBuf[0]) +
  cast[int](fileHeader.PointerToSymbolTable)
)

echo "number of symbols: " & $fileHeader.NumberOfSymbols
echo "number of sections: " & $fileHeader.NumberOfSections
echo "pointer to symbol table: 0x" & $toHex(fileHeader.PointerToSymbolTable)

# for i in 0..(fileHeader.NumberOfSymbols):
#   let sym: ptr SymbolTableEntry = (symbolArray + cast[int](fileHeader.NumberOfSymbols))

#   echo sym.Type

# we will store our sections here
var sections: seq[tuple[
  name: string, offset: uint64, header: ptr SectionHeader, number: int
]]
var textSectionHeader: ptr SectionHeader 

# for each section, we will append it to our sections sequence
# and calculate the offset from the beginning of sections to it

var sectionMapping: array[25, LPVOID]
var functionMapping: LPVOID

var totalSize: uint64 = 0
for i in 0..(cast[int](fileHeader.NumberOfSections) - 1):
  let sectionHeader: ptr SectionHeader = (sectionArray + i)
  let sectionName = $(unsafeAddr sectionHeader.Name[0])

  # store the text section header separately
  if sectionName == ".text":
    textSectionHeader = sectionHeader

  echo &"Found {sectionName} @ offset {totalSize}:"
  echo &"\tVirtual Size: {sectionHeader.VirtualSize}"
  echo &"\tVirtual Address: 0x{toHex(sectionHeader.VirtualAddress)}"
  echo &"\tRaw Data Size: {sectionHeader.SizeOfRawData}"
  echo &"\tRaw Data Ptr: 0x{toHex(sectionHeader.PointerToRawData)}"
  echo &"\tRelocations Ptr: 0x{toHex(sectionHeader.PointerToRelocations)}"
  echo &"\tLine numbers Ptr: {sectionHeader.PointerToLinenumbers}"
  echo &"\tRelocations Count: {sectionHeader.NumberOfRelocations}"
  echo &"\tLine Count: {sectionHeader.NumberOfLinenumbers}"
  echo &"\tCharacteristics: {sectionHeader.Characteristics}"
  
  echo &"\tAllocating 0x{toHex(sectionHeader.SizeOfRawData)}"

  sectionMapping[i] = VirtualAlloc(
    NULL, 
    cast[SIZE_T](sectionHeader.SizeOfRawData), 
    bitor(MEM_COMMIT, MEM_RESERVE, MEM_TOP_DOWN),
    PAGE_EXECUTE_READWRITE
  )

  if sectionMapping[i] != NULL: 
    echo "\tAllocated successully, copying data"
    copyMem(
      sectionMapping[i],
      (unsafeAddr fileBuf[0]) + cast[int](sectionHeader.PointerToRawData),
      sectionHeader.SizeOfRawData
    )
  else: echo "\tFailed to allocate"

  sections.add (name: sectionName, offset: totalSize, header: sectionHeader, number: i)
  totalSize += sectionHeader.SizeOfRawData

functionMapping = VirtualAlloc(
  NULL, 
  2048, 
  bitor(MEM_COMMIT, MEM_RESERVE, MEM_TOP_DOWN), 
  PAGE_EXECUTE_READWRITE
)
var fmCount = 0

let symVals: ptr char = cast[ptr char](symbolArray + cast[int](fileHeader.NumberOfSymbols))

echo "\nDoing relocations.."

for section in sections:
  echo &"Relocations for section: {section.name}"

  let relocationArray: ptr RelocationTableEntry = cast[ptr RelocationTableEntry](
    (unsafeAddr fileBuf[0]) + 
    cast[int](section.header.PointerToRelocations)
  )
  
  for i in 0..(cast[int](section.header.NumberOfRelocations) - 1):
    let relocation = relocationArray[i]
    echo &"Virtual Address: 0x{toHex(relocation.VirtualAddress)} (SYMBOL: {relocation.SymbolTableIndex}; Type: 0x{toHex(relocation.Type)})"
    let symbolEntry: SymbolTableEntry = symbolArray[cast[int](relocation.SymbolTableIndex)]   
    let symbolPtr = symbolEntry.First.value[1]
    echo &"\tSymPtr: 0x{toHex symbolPtr}"

    let sectionIndex = section.number
    echo &"\tSection Index: {symbolEntry.SectionNumber - 1}"
    let patchAddress = cast[ptr byte](
      cast[int](sectionMapping[sectionIndex]) + 
      cast[int](relocation.VirtualAddress)
    )

    if cast[int](symbolEntry.First.Name[0]) != 0:
      let symname = $(unsafeAddr symbolEntry.First.Name[0])
      echo &"\tSymName: {symname}"

      if relocation.Type == IMAGE_REL_AMD64_ADDR64:
        var offsetVal: uint64
        copyMem(
          addr offsetVal, 
          patchAddress, 
          sizeof(uint64)
        )
        echo &"\t  OffsetVal:    0x{toHex(offsetVal)}"

        offsetVal += cast[uint64](sectionMapping[sectionIndex])
        
        echo &"\t  NewOffsetVal: 0x{toHex(offsetVal)}"

        copyMem(
          patchAddress,
          addr offsetVal,
          sizeof(uint64)
        )
      elif relocation.Type == IMAGE_REL_AMD64_ADDR32NB:
        var offsetVal: int32
        copyMem(
          addr offsetVal, 
          patchAddress,
          sizeof(int32)
        )
        var refSection = cast[int](sectionMapping[sectionIndex]) + cast[int](offsetVal)
        var endOfReloc = cast[int](sectionMapping[sectionIndex]) + cast[int](relocation.VirtualAddress) + 4
        if endOfReloc - refSection > 0xffffffff:
          echo "- error: alloc > 4 gigs away, exitting"
          quit(1)
        echo &"\t  OffsetVal:  0x{toHex(offsetVal)}"
        echo &"\t  RefSection: 0x{toHex(refSection)}"
        echo &"\t  RelocEnd: 0x{toHex(endOfReloc)}"
        offsetVal = cast[int32](endOfReloc) - cast[int32](refSection)
        echo &"\t  OffsetVal: 0x{toHex(offsetVal)}"
        
        copyMem(
          patchAddress,
          addr offsetVal, 
          sizeof(int32)
        )
      elif relocation.Type == IMAGE_REL_AMD64_REL32:
        var offsetVal: int32
        copyMem(addr offsetVal, patchAddress, sizeof(int32))
        echo &"\t  OffsetVal:  0x{toHex(offsetVal)}"
        if cast[int32](sectionMapping[sectionIndex]) - (cast[int32](patchAddress) + 4) > 0xffffffff:
          echo "- error relocation 4 gigs away"
          quit(0)
        offsetVal += cast[int32](sectionMapping[sectionIndex]) - (cast[int32](patchAddress) + 4)
        copyMem(patchAddress, addr offsetVal, sizeof(int32))
        echo &"\t  OffsetVal:  0x{toHex(offsetVal)}"
      continue

    let symbolValue = $(unsafeAddr (symVals + cast[int](symbolPtr))[0])
    echo &"\tSymVal: {symbolValue}"
    echo &"\tSectionNumber: {symbolEntry.SectionNumber}"
    
    if symbolValue.startsWith("__imp_"):
      echo &"\t  !!!!! Found external symbol !!!!!"
      let library = symbolValue.replace("__imp_", "").split("$")[0]
      let funcName = symbolValue.replace("__imp_", "").split("$")[1]
      echo &"\t  - Library:  {library}"
      echo &"\t  - FuncName: {funcName}"
      let llHandle = LoadLibraryA(library)
      let funcAddress = GetProcAddress(llHandle, funcName)
      if funcAddress == NULL:
        echo "- error couldnt process symbol exitting"
        break

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

      let offsetVal = cast[uint32](cast[int](functionMapping) + (fmCount * 8) - cast[int](patchAddress) + 4)

      copyMem(
        patchAddress,
        unsafeAddr offsetVal,
        sizeof(uint32)
      )

      inc fmCount

type COFFEntry = proc(args:ptr byte, argssize: uint32) {.stdcall.}

for i in 0..(cast[int](fileHeader.NumberOfSymbols) - 1):
  let symbol = symbolArray[i]
  let symbolName = $(unsafeAddr symbol.First.Name[0])
  if symbolName == "go":
    let fPtr = cast[int](sectionMapping[symbol.SectionNumber - 1]) + cast[int](symbol.Value)
    let entry = cast[COFFEntry](fPtr)
    entry(NULL, 0)

echo "Cleaning up allocated memory.."

for allocated in sectionMapping:
  VirtualFree(allocated, 0, MEM_RELEASE)
VirtualFree(functionMapping, 0, MEM_RELEASE)