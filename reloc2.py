import sys, getopt
import re

# parse a <source>.lst file and replace the relocatable address with 
# the correct address
# The address is taken from the CODE offeset in the firmware.map file for the <source>.o
# then shifted to the upper half of the address space (actually in firmware.cfg but not parsed here)
# The simple form just replaces the address
# the next step is to replace the relcatable parts of the data "rr" - but this is more involved.
#  - needs firmware.vice for address of labels.

#-----------------------------------------------------------------------------
# Read a set of addresses for all labels in code
#
labelMap = {}
def readLabelMap():
    try:
        f=open("firmware.vice")
        v = f.readline()
        while v:
            vs = v.split("\n")[0].split(" ")
            labelMap[vs[2].split(".")[1]]=vs[1]
            v = f.readline()
        f.close()
    except:
        print("Can't open file firmware.vice")
        exit(-1)

#-----------------------------------------------------------------------------
# Read the address offsets for code segments for each object file
offsets_rx_dict = {
        #string.o:$
        'objname' : re.compile("(?P<objname>.*)\.o:\n"),
        #    CODE              Offs=0032F1  Size=0000C7  Align=00001  Fill=0000$
        'offset' : re.compile("\s*CODE\s*Offs=(?P<offset>\w+)\s.*\n"),
}
def _parse_offset_line(line):
    for key, rx in offsets_rx_dict.items():
        match = rx.search(line)
        if match:
            return key, match
    return None, None

sourceOffsets = {}
def readOffsets():
    try:
        f=open("firmware.map")
        with f:
            l = f.readline()
            while l:
                key, match = _parse_offset_line(l)
                if key == 'objname':
                    obj=match[1]
                if key == 'offset':
                    #print(obj + " 0x" + match[1])
                    sourceOffsets[obj] = match[1]
                l = f.readline()

        f.close()
    except:
        print("Can't open file firmware.map")
        exit(-1)

#-----------------------------------------------------------------------------
# parse an .lst file adding offset (int) to the reloc addresses in the file
#
source_rx_dict = {
        'l0' : re.compile('^(?P<addr>\w+)r 1               (?P<txt>.*)$'),
        'l1' : re.compile('^(?P<addr>\w+)r 1  (?P<b1>\w\w)           (?P<txt>.*)$'),
        'l2' : re.compile('^(?P<addr>\w+)r 1  (?P<b1>\w\w) (?P<b2>\w\w)        (?P<txt>.*)$'),
        'l3' : re.compile('^(?P<addr>\w+)r 1  (?P<b1>\w\w) (?P<b2>\w\w) (?P<b3>\w\w)     (?P<txt>.*)$'),
        'l4' : re.compile('^(?P<addr>\w+)r 1  (?P<b1>\w\w) (?P<b2>\w\w) (?P<b3>\w\w) (?P<b4>\w\w)  (?P<txt>.*)$'),
}
def _parse_source_line(line):
    for key, rx in source_rx_dict.items():
        match = rx.search(line)
        if match:
            return key, match
    return None, None

def parseSourceFile(filename, offset):
    try:
        f=open(filename)
    except:
        print("Can't open file "+filename)
        exit(-1)

    with f:
        l = f.readline()
        while l.find('.code') == -1:
            l = f.readline()

        l = f.readline()
        while l:
            key, match = _parse_source_line(l)
            if key != None:
                aint = int("0x"+match['addr'],16) + offset + int('0x8000',16)
                ahex = hex(aint)[2:].upper()
            if key == 'l0':
                print (ahex + " " + match['txt'])
            if key == 'l1':
                print (ahex + " " + match['b1'] + " " + match['txt'])
            if key == 'l2':
                print (ahex + " " + match['b1'] + " " + match['b2'] + " " + match['txt'])
            if key == 'l3':
                b2 = match['b2']
                b3 = match['b3']
                if b2 == 'rr' and b3 == 'rr':
                    # replace relocatable bytes of branch instruction
                    b2,b3 = get_branch_address(match['txt'])
                print (ahex + " " + match['b1'] + " " + b2 + " " + b3 + " " + match['txt'])
            if key == 'l4':
                print (ahex + " " + match['b1'] + " " + match['b2'] + " " + match['b3'] + " " + match['b4'] + " " + match['txt'])
            l = f.readline()
            
    f.close()

def get_branch_address(line):
    ba2= "rr"
    ba3= "rr"
    
    #print("LINE >>>> "+line)
    rx =  re.compile('.*\s+(JSR|jsr|LDA|lda|LDY|ldy|LDX|ldx|JMP|jmp|BRA|bra)\s+(?P<label>\w*).*$')
    match = rx.search(line)
    if match:
        #print (match['label'])
        # search for label in the addr/label map
        try:
            addr = labelMap[match['label']]
            if addr:
                ba2 = addr[4:6]
                ba3 = addr[2:4]
        except:
            addr = ""
    return ba2, ba3

def main(argv):
    try: 
        fn = argv[0]
    except:
        print("Bad args")
        exit(1)

    rx =  re.compile('^(\w+)\.lst$')
    match = rx.search(fn)
    if match:
        print("Base Name = " + match[1])
        basename = match[1]
    else:
        print ("Object file offset for "+fn+" not found in firmware.map")
        exit (-1)

    readLabelMap()
    readOffsets()
    offset = sourceOffsets[basename]
    print ("Offset 0x"+offset)
    
    parseSourceFile(fn, int("0x"+offset,16))

if __name__ == "__main__":
   main(sys.argv[1:])
