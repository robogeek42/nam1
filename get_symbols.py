import sys, getopt
import re

labelMap = {}
def readLabelMap():
    try:
        f=open("firmware.vice")
        v = f.readline()
        while v:
            #print(v, file=stderr)
            vs = v.split("\n")[0].split(" ")
            name = vs[2].split(".")[1]
            if name.startswith("@"):
                v = f.readline()
                continue
            if name == "main":
                v = f.readline()
                continue

            labelMap[name]="$"+vs[1]
            v = f.readline()
        f.close()
    except:
        print("Can't open file firmware.vice", file=sys.stderr)
        exit(-1)

def main(argv):
    readLabelMap()

    with open("firmware.symbols", "w") as outfile:
        for lab in labelMap:
                print(f"{lab}={labelMap[lab]}", file=outfile)

if __name__ == "__main__":
   main(sys.argv[1:])
