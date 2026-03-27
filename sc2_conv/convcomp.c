#include <stdio.h>
#include <stdint.h>
#include <string.h>

int DoCompress(unsigned char *in, int len, unsigned char *out)
{
	int i=0;
	int totcnt=0;
	while(i<len)
	{
		//fprintf(stderr,"%d:%c:%02X\n",i,in[i],in[i]);
		if (in[i] != in[i+1])
		{
			// start counting different characters
			int cnt=0;
			int j=i;
			while(j<(len-1) && cnt<126)
			{
				if (in[j] != in[j+1])
				{
					cnt++;
				}
				else
				{
					break;
				}
				j++;
			}
			if (j==len-1)
			{
				cnt++;
				j++;
			}
			if(out)
			{
				out[totcnt] = (cnt | 0x80) & 0xFF;
			}
			//printf("%02X",cnt | 0x80); 
			totcnt++;
			while(i<j)
			{
				if(out)
				{
					out[totcnt] = in[i];
				}
				//printf(" %02X",in[i]);
				totcnt++;
				i++;
			}
			//printf(" ");
		}
		else
		{
			// start counting same characters
			int cnt=0;
			int j=i;
			while(j<(len-1) & cnt<126)
			{
				if (in[j] == in[j+1])
				{
					cnt++;
				}
				else
				{
					break;
				}
				j++;
			}
			if (j==len-1 && in[j]==in[j+1])
			{
				cnt++;
				j++;
			}
			//printf("%02X %02X ",cnt+1, in[i]);
			if(out)
			{
				out[totcnt] = cnt+1;
				out[totcnt+1] = in[i];
			}
			totcnt=totcnt+2;
			
			i=j+1;
		}
	}
	return totcnt;
}

void usage(void)
{
	printf("conv [-i] <Source.SC2> <Destfile>\n");
	printf("  -i : output include file, else output binary\n");
}

void printBlock(FILE *f, uint8_t *ch, int blocksize, int linelen, int fmt)
{
	
    if (fmt==1)
    {
        // header line: compression type and size of block
        fprintf(f, ".byte $%02X,$%02X,$%02X,$%02X,$%02X,$%02X\n",'R','L','E',1, blocksize&0xFF, (blocksize>>8)&0xFF);
        for(int i=0;i<blocksize;i++)
        {
            if((i%linelen)==0)
            {
                fprintf(f, ".byte ");
            }
            fprintf(f, "$%02X", ch[i]);
            if((i%linelen)<(linelen-1))
            {
                fprintf(f, ",");
            }
            else
            {
                fprintf(f, "\n");
            }
        }
        fprintf(f, "\n");
    }
    else
    {
        fprintf(f, "RLE%c%c%c",1, blocksize&0xFF, (blocksize>>8)&0xFF);
        for(int i=0;i<blocksize;i++)
        {
            fprintf(f, "%c", ch[i]);
        }
        //fprintf(f,"%c",0);
    }
}

int main(int argc, char **argv)
{
	char *pszOutFile, *pszInFile;
	FILE *hOutFile, *hInFile;
	uint8_t ch[256*8];
	uint8_t sc2array[14*1024];
	int totCompressedSize=0;
	int totOriginalSize=0;
	const int headerSize=6;
    int firstParam=1;
    int outputInc65=0; // binary as default

	if (argc < firstParam+2)
	{
		usage();
		return -1;
	}

    if (strcmp(argv[1],"-i")==0)
    {
        printf("convert to include file\n");
        outputInc65 = 1;
        firstParam++;

        if (argc < firstParam+2)
        {
            usage();
            return -1;
        }
        
    }
    else
    {
        printf("convert to binary\n");
    }

	pszInFile = argv[firstParam];
	pszOutFile = argv[firstParam+1];

	printf("InFile : %s OutFile : %s\n", argv[1], argv[2]);

	hInFile = fopen(pszInFile, "rb");
	if(!hInFile)
	{
		printf("Failed to open %s\n", pszInFile);
		return -1;
	}
	hOutFile = fopen(pszOutFile, "w");
	if(!hOutFile)
	{
		printf("Failed to open %s\n", pszOutFile);
		fclose(hInFile);
		return -1;
	}

    if(outputInc65)
    {
        fprintf(hOutFile, ";; %s\n",pszInFile);
        fflush(hOutFile);
    }

	/* Skip the Header */
	fseek(hInFile, 7, SEEK_SET);

	// pattern table
	for(int i=0;i<3;i++)
	{
		int bytesread = 0;
		uint8_t outarray[256*8];
		int csize=0;

        if(outputInc65)
        {
            fprintf(hOutFile,";; Pattern Table Block %d\n",i);
            fprintf(hOutFile,"PT_BLK%d:\n",i);
        }
		bytesread = fread(ch, 1, 256*8, hInFile);
		if(bytesread!=256*8)
		{
			printf("Error: fread returned %d\n",bytesread);
			return -1;
		}
		totOriginalSize+=bytesread;
		csize = DoCompress(ch, 256*8, outarray);
		printBlock(hOutFile, outarray, csize, 16, outputInc65);
		totCompressedSize += csize + headerSize;
	}
    if(outputInc65)
    {
        fprintf(hOutFile, "\n");
    }
    fflush(hOutFile);
	
	// color table
	fseek(hInFile, 8192+7, SEEK_SET);
	for(int i=0;i<3;i++)
	{
		int bytesread = 0;
		uint8_t outarray[256*8];
		int csize=0;

        if(outputInc65)
        {
            fprintf(hOutFile,";; Color Table Block %d\n",i);
            fprintf(hOutFile,"CT_BLK%d:\n",i);
        }
		bytesread = fread(ch, 1, 256*8, hInFile);
		if(bytesread!=256*8)
		{
			printf("Error: fread returned %d\n",bytesread);
			return -1;
		}
		totOriginalSize+=bytesread;
		csize = DoCompress(ch, 256*8, outarray);
		printBlock(hOutFile, outarray, csize, 16, outputInc65);
		totCompressedSize += csize + headerSize;
	}
    if(outputInc65)
    {
        fprintf(hOutFile, "\n");
    }
	fflush(hOutFile);

	fclose(hOutFile);

	printf("Size: Original %d Compressed %d : %.2f%%\n",totOriginalSize, totCompressedSize,
			100.0*(totOriginalSize - totCompressedSize)/totOriginalSize);
}
