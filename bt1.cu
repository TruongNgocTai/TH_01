#include <stdio.h>
#include <stdint.h>

#define CHECK(call)                                                            \
{                                                                              \
    const cudaError_t error = call;                                            \
    if (error != cudaSuccess)                                                  \
    {                                                                          \
        fprintf(stderr, "Error: %s:%d, ", __FILE__, __LINE__);                 \
        fprintf(stderr, "code: %d, reason: %s\n", error,                       \
                cudaGetErrorString(error));                                    \
        exit(EXIT_FAILURE);                                                    \
    }                                                                          \
}

struct GpuTimer
{
    cudaEvent_t start;
    cudaEvent_t stop;

    GpuTimer()
    {
        cudaEventCreate(&start);
        cudaEventCreate(&stop);
    }

    ~GpuTimer()
    {
        cudaEventDestroy(start);
        cudaEventDestroy(stop);
    }

    void Start()
    {
        cudaEventRecord(start, 0);
    }

    void Stop()
    {
        cudaEventRecord(stop, 0);
    }

    float Elapsed()
    {
        float elapsed;
        cudaEventSynchronize(stop);
        cudaEventElapsedTime(&elapsed, start, stop);
        return elapsed;
    }
};

void readPnm(char * fileName, int &numChannels, int &width, int &height, uint8_t * &pixels)
{
	FILE * f = fopen(fileName, "r");
	if (f == NULL)
	{
		printf("Cannot read %s\n", fileName);
		exit(EXIT_FAILURE);
	}

	char type[3];
	fscanf(f, "%s", type);
	if (strcmp(type, "P2") == 0)
		numChannels = 1;
	else if (strcmp(type, "P3") == 0)
		numChannels = 3;
	else 
	{
		fclose(f);
		printf("Cannot read %s\n", fileName); // In this exercise, we don't touch other types
		exit(EXIT_FAILURE); 
	}

	fscanf(f, "%i", &width);
	fscanf(f, "%i", &height);
	
	uint8_t max_val;
	fscanf(f, "%hhu", &max_val);
	if (max_val > 255)
	{
		fclose(f);
		printf("Cannot read %s\n", fileName); // In this exercise, we assume 1 byte per value
		exit(EXIT_FAILURE); 
	}

	pixels = (uint8_t *)malloc(width * height * numChannels);
	for (int i = 0; i < width * height * numChannels; i++)
		fscanf(f, "%hhu", &pixels[i]);

	fclose(f);
}

void writePnm(char * fileName, int numChannels, int width, int height, uint8_t * pixels)
{
	FILE * f = fopen(fileName, "w");
	if (f == NULL)
	{
		printf("Cannot write %s\n", fileName);
		exit(EXIT_FAILURE);
	}	
	
	if (numChannels == 1)
		fprintf(f, "P2\n");
	else if (numChannels == 3)
		fprintf(f, "P3\n");
	else
	{
		fclose(f);
		printf("Cannot write %s\n", fileName);
		exit(EXIT_FAILURE);
	}

	fprintf(f, "%i\n%i\n255\n", width, height); 

	for (int i = 0; i < width * height * numChannels; i++)
		fprintf(f, "%hhu\n", pixels[i]);
	
	fclose(f);
}

void compare2Pnms(char * fileName1, char * fileName2)
{
	int numChannels1, width1, height1;
	uint8_t * pixels1;
	readPnm(fileName1, numChannels1, width1, height1, pixels1);

	int numChannels2, width2, height2;
	uint8_t * pixels2;
	readPnm(fileName2, numChannels2, width2, height2, pixels2);

	if (numChannels1 != numChannels2)
	{
		printf("'%s' is DIFFERENT from '%s' (num channels: %i vs %i)\n", fileName1, fileName2, numChannels1, numChannels2);
		return;
	}
	if (width1 != width2)
	{
		printf("'%s' is DIFFERENT from '%s' (width: %i vs %i)\n", fileName1, fileName2, width1, width2);
		return;
	}
	if (height1 != height2)
	{
		printf("'%s' is DIFFERENT from '%s' (width: %i vs %i)\n", fileName1, fileName2, height1, height2);
		return;
	}
	float mae = 0;
	for (int i = 0; i < width1 * height1 * numChannels1; i++)
	{
		mae += abs((int)pixels1[i]-(int)pixels2[i]);
	}
	mae /= (width1 * height1 * numChannels1);
	printf("The average pixel difference between '%s' and '%s': %f\n", fileName1, fileName2, mae);
}

void convertRgb2GrayByHost(uint8_t * inPixels, uint8_t * outPixels, int width, int height)
{
	// TODO
	int size = width * height;

	for(int i = 0; i < size; i++){
		outPixels[i] = 0.299 * inPixels[i*3] +
						 0.114 * inPixels[i*3 + 2] + 
						 0.587 * inPixels[i*3 + 1];
	}
}

__global__ void convertRgb2GrayByDevice(uint8_t * inPixels, uint8_t * outPixels, int width, int height)
{
	// TODO
	int i_r = blockIdx.y * blockDim.y + threadIdx.y;
	int i_c = blockIdx.x * blockDim.x + threadIdx.x;

	if(i_c < width && i_r < height){
		outPixels[i_r * width + i_c] = 0.299 * inPixels[(i_r * width + i_c)*3] + 
										0.114 * inPixels[(i_r * width + i_c)*3 + 2] + 
										0.587 * inPixels[(i_r * width + i_c)*3 + 1];
	}
}


int main(int argc, char ** argv)
{
	// -----READ INPUT DATA-----
	if (argc < 5 || argc > 7)
	{
		printf("The number of arguments is invalid\n");
		return EXIT_FAILURE;
	}

	int numChannels, width, height;
	uint8_t * inPixels;
	readPnm(argv[1], numChannels, width, height, inPixels);
	printf("Image size (width x height): %i x %i\n", width, height);
	// -----PROCESS INPUT DATA-----
	uint8_t * outPixels= (uint8_t *)malloc(width * height);
	GpuTimer timer;
    timer.Start();
	if (strcmp(argv[4], "cpu") == 0){ // Use CPU
		convertRgb2GrayByHost(inPixels, outPixels, width, height);
	}
	else // Use GPU
	{
		// TODO: Query and print GPU name and compute capability
		cudaDeviceProp prop;
		printf("GPU name: %s\n", prop.name);
		printf("GPU compute capability: %d\n", prop.major);
		printf("GPU compute capability: %d\n", prop.minor);

		// TODO: Allocate device memories
		uint8_t *d_inPixels, *d_outPixels;
		CHECK(cudaMalloc(&d_inPixels, width * height * numChannels));
		CHECK(cudaMalloc(&d_outPixels, width * height));

		// TODO: Copy data to device memories
		CHECK(cudaMemcpy(d_inPixels, inPixels, width * height * numChannels, cudaMemcpyHostToDevice));

		// TODO: Set block size (already done for you) and grid size,
		//       and invoke kernel function with these settings (remember to check kernel error)
		dim3 blockSize(32, 32); // Default
		if (argc == 7)
		{
			blockSize.x = atoi(argv[5]);
			blockSize.y = atoi(argv[6]);
		}
		dim3 gridSize(16, 16);
		convertRgb2GrayByDevice<<<gridSize, blockSize>>>(d_inPixels, d_outPixels, width, height);

		// TODO: Copy result from device memories
		CHECK(cudaMemcpy(outPixels, d_outPixels, width * height, cudaMemcpyDeviceToHost));

		// TODO: Free device memories
		cudaFree(d_inPixels);
		cudaFree(d_outPixels);
	}
	timer.Stop();
    float time = timer.Elapsed();
    printf("Processing time: %f ms\n", time);

    // -----WRITE OUTPUT DATA TO FILE-----
	writePnm(argv[2], 1, width, height, outPixels);

	free(inPixels);
	free(outPixels);

	// -----CHECK CORRECTNESS-----
	compare2Pnms(argv[2], argv[3]);
}