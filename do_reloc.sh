# Relocate ambiguous addresses in lst files
# and combine into a single file in out/all.lst

for f in *.lst 
do
    python reloc2.py $f > out/$f 
done

cd out 
cat main.lst acia.lst print_util.lst string.lst bcd.lst \
    sd.lst pckybd.lst sound.lst video_common.lst \
    video.lst sprite.lst decomp.lst pm.lst > all.lst
cd -
