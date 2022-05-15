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
        print("Can't open file firmware.vice", file=sys.stderr)
        exit(-1)

    # Add special VDP_VARS from video_vars.inc65
    vaddr = labelMap['VDP_VARS']
    labelMap['VDP_CHAR_WIDTH'] = _hex_str_add(vaddr, 1)
    labelMap['VDP_SAB'] = _hex_str_add(vaddr, 2)
    labelMap['VDP_CURS'] = _hex_str_add(vaddr, 4)
    labelMap['VDP_XPOS'] = _hex_str_add(vaddr, 6)
    labelMap['VDP_YPOS'] = _hex_str_add(vaddr, 7)
    labelMap['VDP_STATUS'] = _hex_str_add(vaddr, 8)

def _hex_str_add(v,n):
    hh = "00"+hex(int("0x"+v,16) + n)[2:]
    hh = hh.upper()
    #print(hh, file=sys.stderr)
    return hh

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
        'l0' : re.compile('^(?P<addr>\w+)r (?P<fnum>\d)               (?P<txt>.*)$'),
        'l1' : re.compile('^(?P<addr>\w+)r (?P<fnum>\d)  (?P<b1>\w\w)           (?P<txt>.*)$'),
        'l2' : re.compile('^(?P<addr>\w+)r (?P<fnum>\d)  (?P<b1>\w\w) (?P<b2>\w\w)        (?P<txt>.*)$'),
        'l3' : re.compile('^(?P<addr>\w+)r (?P<fnum>\d)  (?P<b1>\w\w) (?P<b2>\w\w) (?P<b3>\w\w)     (?P<txt>.*)$'),
        'l4' : re.compile('^(?P<addr>\w+)r (?P<fnum>\d)  (?P<b1>\w\w) (?P<b2>\w\w) (?P<b3>\w\w) (?P<b4>\w\w)  (?P<txt>.*)$'),
}
def _parse_source_line(line):
    for key, rx in source_rx_dict.items():
        match = rx.search(line)
        if match:
            return key, match
    return None, None

def parseSourceFile(filename, offset, ismain, ff):
    try:
        f=open(filename)
    except:
        print("Can't open file "+filename)
        exit(-1)

    with f:
        skipcnt=0
        l = f.readline()
        skipcnt=skipcnt+1
        while l.find('.code') == -1:
            l = f.readline()
            skipcnt=skipcnt+1
        print("Skip count "+str(skipcnt), file=sys.stderr)

        l = f.readline()
        while l:
            key, match = _parse_source_line(l)
            if key != None:
                aint = int("0x"+match['addr'],16) + offset + int('0x8000',16)
                ahex = '00'+hex(aint)[2:].upper()
            if key == 'l0':
                if ismain==True or match['fnum']=='1':
                    print (ahex + "             " + match['txt'], file=ff)
            if key == 'l1':
                if ismain==True or match['fnum']=='1':
                    print (ahex + " " + match['b1'] + "          " + match['txt'], file=ff)
            if key == 'l2':
                if ismain==True or match['fnum']=='1':
                    print (ahex + " " + match['b1'] + " " + match['b2'] + "       " + match['txt'], file=ff)
            if key == 'l3':
                b2 = match['b2']
                b3 = match['b3']
                if b2 == 'rr' and b3 == 'rr':
                    # replace relocatable bytes of branch instruction
                    b2,b3 = get_branch_address(match['txt'])
                if ismain==True or match['fnum']=='1':
                    print (ahex + " " + match['b1'] + " " + b2 + " " + b3 + "    " + match['txt'], file=ff)
            if key == 'l4':
                if ismain==True or match['fnum']=='1':
                    print (ahex + " " + match['b1'] + " " + match['b2'] + " " + match['b3'] + " " + match['b4'] + " " + match['txt'], file=ff)
            l = f.readline()
            
    f.close()

bra='JSR|LDA|LDY|LDX|JMP|BRA|INC|STA|STX|STY|STZ'
branch_rx_dict = {
        'lab_normal' : re.compile('.*\s+('+bra+'|'+bra.lower()+')\s+(?P<label>\w*).*$'),
        'lab_plus' : re.compile('.*\s+('+bra+'|'+bra.lower()+')\s+(?P<label>\w*)\+(?P<plus>\d+).*$'),
}
def get_branch_address(line):
    ba2= "ss"
    ba3= "ss"
    
    rx = branch_rx_dict['lab_plus']
    match = rx.search(line)
    if match:
        #print("Match plus", file=sys.stderr)
        #print(match, file=sys.stderr)
        try:
            addr = labelMap[match['label']]
            if addr:
                int_addr = int("0x"+addr,16)
                int_newaddr = int_addr + int(match['plus'])
                newaddr = hex(int_newaddr).upper()
                #print(match['label'] + " + " + match['plus'] + " -> " + newaddr, file=sys.stderr)
                ba2 = newaddr[4:6]
                ba3 = newaddr[2:4]
        except:
            print("Did not find branch addr and plus for "+match['label']+" ", file=sys.stderr);
            addr = ""
        return ba2, ba3

    #print("LINE >>>> "+line, file=sys.stderr)
    rx = branch_rx_dict['lab_normal']
    match = rx.search(line)
    if match:
        #print (match['label'], file=sys.stderr)
        # search for label in the addr/label map
        try:
            addr = labelMap[match['label']].upper()
            #print(match['label'] + " > " + addr, file=sys.stderr)
            if addr:
                ba2 = addr[4:6]
                ba3 = addr[2:4]
        except:
            print("Did not find branch addr for "+match['label']+" ", file=sys.stderr);
            addr = ""
        return ba2, ba3

    return ba2, ba3


def getBasename(fn):
    rx =  re.compile('^(\w+)\.lst$')
    match = rx.search(fn)
    if match:
        print("Base Name = " + match[1], file=sys.stderr)
        return match[1]
    else:
        print ("Can't parse basename for "+fn+" Should be an lst file", file=sys.stderr)
        return None

def main(argv):
    singleFile = False
    isMain = False
    if len(argv)==1: 
        fn = argv[0]
        singleFile = True
    elif len(argv)==0:
        print("All files - create .r files:", file=sys.stderr)
    else:
        print("Error: pass one file or none", file=sys.stderr)
        exit(-1)

    readLabelMap()
    readOffsets()

    # test a single file at a time
    if singleFile:
        basename = getBasename(fn)
        if basename=='main':
            isMain=True
        print("Process file "+basename+" :",file=sys.stderr)
        if basename:
            offset = sourceOffsets[basename]
            print ("Offset 0x"+offset, file=sys.stderr)
            parseSourceFile(fn, int("0x"+offset,16), isMain, sys.stdout)
        exit(0)

    # This is the concatenating version
    for fn in sourceOffsets.keys():
        print("Process file "+fn+".lst"+" :",file=sys.stderr)
        if fn=='main':
            isMain=True
        offset = sourceOffsets[fn]
        print ("Offset 0x"+offset, file=sys.stderr)
        try:
            ofname = fn+'.reloc'
            outfile = open(ofname,'w')
            parseSourceFile(fn+".lst", int("0x"+offset,16), isMain, outfile)
            outfile.close()
        except:
            print("failed to open or write to "+ofname, file=sys.stderr)
    print("Concatenate to firmware.reloc", file=sys.stderr)
    with open('firmware.reloc', 'wb') as catfile:
        for fn in sourceOffsets.keys():
            print("File: "+fn+".reloc", file=sys.stderr)
            infile = open(""+fn+".reloc","rb")
            catfile.write(infile.read())





if __name__ == "__main__":
   main(sys.argv[1:])
