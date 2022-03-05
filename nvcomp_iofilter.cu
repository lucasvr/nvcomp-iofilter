#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <hdf5.h>

#include <nvcomp/snappy.hpp>
#include <nvcomp.hpp>

#include "nvcomp_iofilter.h"

using namespace nvcomp;

bool compress(void **buf, size_t *buf_size, size_t *compressed_size)
{
    bool retval = true;

    // Copy input data to device memory
    uint8_t *uncomp_buf;
    cudaMalloc(&uncomp_buf, *buf_size);
    cudaMemcpy(uncomp_buf, *buf, *buf_size, cudaMemcpyDefault);

    // Create stream
    cudaStream_t stream;
    cudaStreamCreate(&stream);

    // Configure nvCOMP manager
    const int chunk_size = 1 << 16;
    SnappyManager nvcomp_manager{chunk_size, stream};
    CompressionConfig comp_config = nvcomp_manager.configure_compression(*buf_size);

    // Compress
    uint8_t *comp_buffer;
    cudaMalloc(&comp_buffer, comp_config.max_compressed_buffer_size);
    nvcomp_manager.compress(uncomp_buf, comp_buffer, comp_config);
    size_t output_size = nvcomp_manager.get_compressed_output_size(comp_buffer);
    cudaStreamSynchronize(stream);

    // Handle the unexpected case in which the output buffer is too small
    // (i.e., we must be compressing random data)
    if (*buf_size < output_size) {
        char *newbuf = (char *) malloc(sizeof(char) * output_size);
        if (! newbuf) {
            fprintf(stderr, "Not enough memory to hold the compressed data\n");
            retval = false;
        } else {
            free(*buf);
            *buf = newbuf;
            *buf_size = output_size;
        }
    }

    // Replace input data with output data
    if (retval) {
        cudaMemcpy(*buf, comp_buffer, output_size, cudaMemcpyDefault);
        *compressed_size = output_size;
    }

    cudaFree(comp_buffer);
    cudaFree(uncomp_buf);
    cudaStreamDestroy(stream);
    return retval;
}

bool uncompress(void **buf, size_t *buf_size, size_t *uncompressed_size)
{
    // Copy input data to device memory
    uint8_t *comp_buffer;
    cudaMalloc(&comp_buffer, *buf_size);
    cudaMemcpy(comp_buffer, *buf, *buf_size, cudaMemcpyDefault);

    // Create stream
    cudaStream_t stream;
    cudaStreamCreate(&stream);

    // Configure nvCOMP manager
    const int chunk_size = 1 << 16;
    SnappyManager nvcomp_manager{chunk_size, stream};
    DecompressionConfig decomp_config = nvcomp_manager.configure_decompression(comp_buffer);
    size_t output_size = decomp_config.decomp_data_size;

    // Uncompress
    uint8_t *uncomp_buffer;
    cudaMalloc(&uncomp_buffer, output_size);
    nvcomp_manager.decompress(uncomp_buffer, comp_buffer, decomp_config);
    cudaStreamSynchronize(stream);

    // Replace input with output data
    if (*buf_size < output_size) {
        // The buffer provided by HDF5 is not large enough to hold the uncompressed data
        char *newbuf = (char *) malloc(sizeof(char) * output_size);
        if (! newbuf) {
            fprintf(stderr, "Not enough memory to hold the uncompressed data\n");
            return false;
        }
        free(*buf);
        *buf = newbuf;
        *buf_size = output_size;
    }
    cudaMemcpy(*buf, uncomp_buffer, output_size, cudaMemcpyDefault);
    *uncompressed_size = output_size;

    cudaFree(uncomp_buffer);
    cudaFree(comp_buffer);
    cudaStreamDestroy(stream);
    return true;
}

static size_t filter_callback(unsigned int flags, size_t cd_nelmts,
    const unsigned int *cd_values, size_t nbytes, size_t *buf_size, void **buf)
{
    size_t output_size = 0;

    if (flags & H5Z_FLAG_REVERSE) {
        if (uncompress(buf, buf_size, &output_size) == false)
            return 0;
    } else {
        if (compress(buf, buf_size, &output_size) == false)
            return 0;
    }

    return output_size;
}

extern "C" const H5Z_class2_t NVCOMP_FILTER[1] = {{
    H5Z_CLASS_T_VERS,
    NVCOMP_FILTER_ID,
    1, 1,
    "nvcomp_filter",
    NULL, /* can_apply */
    NULL, /* set_local */
    filter_callback,
}};

extern "C" H5PL_type_t H5PLget_plugin_type(void) { return H5PL_TYPE_FILTER; }
extern "C" const void *H5PLget_plugin_info(void) { return NVCOMP_FILTER; }
