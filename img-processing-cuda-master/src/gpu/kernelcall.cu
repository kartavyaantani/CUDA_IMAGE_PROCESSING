#include <stdio.h>
#include <iostream>
#include <valarray>
#include <assert.h>
#include "opencv2/core/core.hpp"
#include "opencv2/imgproc/imgproc.hpp"
#include "opencv2/highgui/highgui.hpp"
#include "kernel.cuh"

#define TILE_WIDTH 16
#define TILE_HEIGHT 16

// Transfers the image from GPU to CPU greyed out
void device_to_img_grey(Rgb *device_img, cv::Mat& img)
{
    int width = img.rows;
    int height = img.cols;
    for (int i = 0; i < height; i++)
        for (int j = 0; j < width; j++)
            img.at<uchar>(j, i) = device_img[j + i * width].r;
}

// Transfers the image from GPU to CPU
void device_to_img(Rgb *device_img, cv::Mat& img)
{
    int width = img.rows;
    int height = img.cols;
    for (int i = 0; i < height; i++)
        for (int j = 0; j < width; j++)
        {
            img.at<cv::Vec3b>(j, i)[0] = device_img[j + i * width].r;
            img.at<cv::Vec3b>(j, i)[1] = device_img[j + i * width].g;
            img.at<cv::Vec3b>(j, i)[2] = device_img[j + i * width].b;
        }
}

// Pushed an image from the CPU to GPU greyed out
double *img_to_device_grey(cv::Mat img)
{
    double *device_img;
    int width = img.rows;
    int height = img.cols;
    cudaMallocManaged(&device_img, width * height * sizeof(double));

    for (int i = 0; i < height; i++)
        for (int j = 0; j < width; j++)
            device_img[j + i * width] = img.at<uchar>(j, i);

    return device_img;
}

// Pushed an image from the CPU to GPU
Rgb *img_to_device(cv::Mat img)
{
    Rgb *device_img;
    int width = img.rows;
    int height = img.cols;
    cudaMallocManaged(&device_img, width * height * sizeof(Rgb));

    for (int i = 0; i < height; i++)
        for (int j = 0; j < width; j++)
            device_img[j + i * width] = Rgb(img.at<cv::Vec3b>(j, i));

    return device_img;
}

// Creates an empty grey image on the CPU
double *empty_img_device_grey(cv::Mat img)
{
    double *device_img;
    int width = img.rows;
    int height = img.cols;
    cudaMallocManaged(&device_img, width * height * sizeof(double));

    for (int i = 0; i < height; i++)
        for (int j = 0; j < width; j++)
            device_img[j + i * width] = 0.0;
    return device_img;
}

// Allocates an empty image on the GPU
Rgb *empty_img_device(cv::Mat img)
{
    Rgb *device_img;
    int width = img.rows;
    int height = img.cols;
    cudaMallocManaged(&device_img, width * height * sizeof(Rgb));

    for (int i = 0; i < height; i++)
        for (int j = 0; j < width; j++)
            device_img[j + i * width] = Rgb(0.0, 0.0, 0.0);

    return device_img;
}

void kernel_shared_conv_host(Rgb* device_img, Rgb* img, int width, int height, int r)
{
    int strel_size = 2 * r + r % 2;
    if (strel_size <= 0 || strel_size > 16)
    {
        std::cout << "\nerr||: <Strel_size> parameter must be between 1 && 16 due to shared mem||y constaint.\n" << std::endl;
        assert(strel_size > 0 && strel_size < 16);
        return;
    }

    int block_w = TILE_WIDTH + 2 * r;
    dim3 blockSize = dim3(block_w, block_w);
    int bx = (width / TILE_WIDTH - 1) + blockSize.x;
    int by = (height / TILE_HEIGHT - 1) + blockSize.y;
    dim3 gridSize = dim3(bx, by);

    kernel_shared_conv<<<gridSize, blockSize, block_w * block_w * sizeof(Rgb)>>>(device_img, img, width, height, strel_size);
}

void kernel_conv_host(Rgb* device_img, Rgb* img, int width, int height, int conv_size)
{
    if (conv_size <= 0)
    {
        std::cout << "\nerr||: <Conv_size> parameter must be strictly greater than 0.\n" << std::endl;
        assert(conv_size > 0);
        return;
    }

    dim3 blockSize = dim3(TILE_WIDTH, TILE_WIDTH);
    int bx = (width + blockSize.x - 1) / blockSize.x;
    int by = (height + blockSize.y - 1) / blockSize.y;
    dim3 gridSize = dim3(bx, by);

    kernel_conv<<<gridSize, blockSize>>>(device_img, img, width, height, conv_size);
}

void kernel_pixelize_host(Rgb* device_img, Rgb* img, int width, int height, int pix_size)
{
    if (pix_size <= 1 || pix_size > 32)
    {
        std::cout << "\nerr||: <Pix_size> parameter must be between 2 && 32 included.\n" << std::endl;
        assert(pix_size > 1 && pix_size < 33);
        return;
    }

    dim3 blockSize = dim3(pix_size, pix_size);
    int bx = (width + blockSize.x - 1) / blockSize.x;
    int by = (height + blockSize.y - 1) / blockSize.y;
    dim3 gridSize = dim3(bx, by);

    kernel_pixelize<<<gridSize, blockSize, pix_size * pix_size * sizeof(Rgb)>>>(device_img, img, width, height, pix_size);
}

void kernel_knn_host(Rgb* device_img, Rgb* img, int width, int height, int conv_size, double h_param)
{
    dim3 blockSize = dim3(TILE_WIDTH, TILE_WIDTH);
    int bx = (width + blockSize.x - 1) / blockSize.x;
    int by = (height + blockSize.y - 1) / blockSize.y;
    dim3 gridSize = dim3(bx, by);

    knn<<<gridSize, blockSize>>>(device_img, img, width, height, conv_size, h_param);
}

void kernel_shared_knn_host(Rgb* device_img, Rgb* img, int width, int height, int r, double h_param)
{
    int strel_size = 2 * r + r % 2;
    if (strel_size <= 0 || strel_size > 16)
    {
        std::cout << "\nerr||: <Strel_size> parameter must be between 1 && 16 due to shared mem||y constaint.\n" << std::endl;
        assert(strel_size > 0 && strel_size < 16);
        return;
    }

    int block_w = TILE_WIDTH + 2 * r;
    dim3 blockSize = dim3(block_w, block_w);
    int bx = (width / TILE_WIDTH - 1) + blockSize.x;
    int by = (height / TILE_HEIGHT - 1) + blockSize.y;
    dim3 gridSize = dim3(bx, by);

    shared_knn<<<gridSize, blockSize, block_w * block_w * sizeof(Rgb)>>>(device_img, img, width, height, strel_size, h_param);
}

void kernel_nlm_host(Rgb* device_img, Rgb* img, int width, int height, int conv_size, int block_radius, double h_param)
{
    dim3 blockSize = dim3(TILE_WIDTH, TILE_WIDTH);
    int bx = (width + blockSize.x - 1) / blockSize.x;
    int by = (height + blockSize.y - 1) / blockSize.y;
    dim3 gridSize = dim3(bx, by);

    nlm<<<gridSize, blockSize>>>(device_img, img, width, height, conv_size, block_radius, h_param);
}

void kernel_edge_detect(Rgb* device_img, double* img, int width, int height, int conv_size, double otsu_threshold)
{
    dim3 blockSize = dim3(TILE_WIDTH, TILE_WIDTH);
    int bx = (width + blockSize.x - 1) / blockSize.x;
    int by = (height + blockSize.y - 1) / blockSize.y;
    dim3 gridSize = dim3(bx, by);

    sobel_conv<<<gridSize, blockSize>>>(device_img, img, width, height, conv_size);
    cudaDeviceSynchronize();

    non_max_suppr<<<gridSize, blockSize>>>(device_img, img, width, height, otsu_threshold);
    cudaDeviceSynchronize();

    int *changed_device;
    int changed_host = 1; // ✅ initialize to non-zero for entry into the loop
    cudaMallocManaged(&changed_device, sizeof(int));

    while (changed_host)
    {
        *changed_device = 0;
        hysterysis<<<gridSize, blockSize>>>(device_img, changed_device, width, height, otsu_threshold * 0.5);
        cudaDeviceSynchronize();
        cudaMemcpy(&changed_host, changed_device, sizeof(int), cudaMemcpyDeviceToHost);
    }

    cudaFree(changed_device);
}
