#include <stdio.h>
#include <stdint.h>

void usage(void)
{
	printf("conv <Source.SC2> <Destfile>\n");
}

void printBlock(FILE *f, uint8_t *ch, int blocksize, int linelen)
{
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
}

int main(int argc, char **argv)
{
	char *pszOutFile, *pszInFile;
	FILE *hOutFile, *hInFile;
	uint8_t ch[256*8];

	if (argc < 3)
	{
		usage();
		return -1;
	}

	pszInFile = argv[1];
	pszOutFile = argv[2];
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

	fprintf(hOutFile, ";; %s\n",pszInFile);
	fflush(hOutFile);

	/* Skip the Header */
	fseek(hInFile, 7, SEEK_SET);

	// pattern table
	for(int i=0;i<3;i++)
	{
		int bytesread = 0;
		fprintf(hOutFile,";; Pattern Table Block %d\n",i);
		fprintf(hOutFile,"PT_BLK%d:\n",i);
		bytesread = fread(ch, 1, 256*8, hInFile);
		if(bytesread!=256*8)
		{
			printf("Error: fread returned %d\n",bytesread);
			return -1;
		}
		printBlock(hOutFile, ch, 256*8, 16);
	}
	fprintf(hOutFile, "\n");
	fflush(hOutFile);
	
	// color table
	fseek(hInFile, 8192+7, SEEK_SET);
	for(int i=0;i<3;i++)
	{
		int bytesread = 0;
		fprintf(hOutFile,";; Color Table Block %d\n",i);
		fprintf(hOutFile,"CT_BLK%d:\n",i);
		bytesread = fread(ch, 1, 256*8, hInFile);
		if(bytesread!=256*8)
		{
			printf("Error: fread returned %d\n",bytesread);
			return -1;
		}
		printBlock(hOutFile, ch, 256*8, 16);
	}
	fprintf(hOutFile, "\n");
	fflush(hOutFile);

	fclose(hOutFile);
	fclose(hInFile);
}
