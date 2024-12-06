#include <metal_stdlib>
using namespace metal;

/**
 * 6-Bit Quantized Linear.
 *
 * @param[A] M x K unquantized input tensor of floating point dtype (Float, Half, BFloat16)
 * @param[B] Packed & quantized weight tensor of uint8 dtype. Expected shape is N x (6 * K / 8)
 * @param[scales] 2D tensor containg the scales for each group. Expected shape is #groups x N
 * @param[zeros] 2D tensor containg the zero points for each group. Expected shape is #groups x N
 * @param[outputData] M x N output tensor of floating point dtype (same as input)
 * @param[sizes] The sizes involved in the order: M, K, N
 *
 * Dispatched threads: N x M x 1
 */
template<typename T, unsigned groupSize>
kernel void int6pack_mm(
    constant T                 * A              [[buffer(0)]],
    constant uchar             * B              [[buffer(1)]],
    constant T                 * scales         [[buffer(2)]],
    constant T                 * zeros          [[buffer(3)]],
    device   T                 * outputData     [[buffer(4)]],
    constant uint3             & sizes          [[buffer(5)]], // M, K, N
    uint2                        thread_index   [[thread_position_in_grid]]) {
    const uint K = sizes.y;
    const uint N = sizes.z;
    const uint m = thread_index.y; // 0..M-1
    const uint n = thread_index.x; // 0..N-1
    const uint32_t k_block = (K + groupSize - 1) / groupSize;
    constant T *A_ptr = A + m * K;
    constant uchar *B_ptr = B + n * 3 * K / 4;

    float rc = 0.0;
    uint k = 0;
    for (uint32_t kb = 0; kb < k_block ; kb ++) {
      const float scale = float(scales[kb * N + n]);
      const float zero = float(zeros[kb * N + n]);
      for(uint idx = 0; idx < groupSize && k < K; idx+=4, k+=4) {
        const auto a_val0 = float(A_ptr[k + 0]);
        const auto a_val1 = float(A_ptr[k + 1]);
        const auto a_val2 = float(A_ptr[k + 2]);
        const auto a_val3 = float(A_ptr[k + 3]);

        uchar b0 = B_ptr[3 * (k / 4) + 0];
        uchar b1 = B_ptr[3 * (k / 4) + 1];
        uchar b2 = B_ptr[3 * (k / 4) + 2];

        uchar w_val0 = ((b0 & 3) << 4) | (b1 & 15);
        uchar w_val1 = ((b0 & 12) << 2) | ((b1 & 240) >> 4);
        uchar w_val2 = ((b0 & 48)) | (b2 & 15);
        uchar w_val3 = ((b0 & 192) >> 2) | ((b2 & 240) >> 4);

        rc += a_val0 * (scale * float(w_val0) + zero);
        rc += a_val1 * (scale * float(w_val1) + zero);
        rc += a_val2 * (scale * float(w_val2) + zero);
        rc += a_val3 * (scale * float(w_val3) + zero);
      }
    }
    outputData[m * N + n] = T(rc);
}

#define INSTANTIATE_INT6MM(DTYPE, GSIZE)                                 \
template                                                                 \
[[host_name("int6pack_mm_" #GSIZE "_" #DTYPE)]]                          \
kernel void int6pack_mm<DTYPE, GSIZE>(                                   \
    constant DTYPE             * A              [[buffer(0)]],           \
    constant uchar             * B              [[buffer(1)]],           \
    constant DTYPE             * scales         [[buffer(2)]],           \
    constant DTYPE             * zeros          [[buffer(3)]],           \
    device   DTYPE             * outputData     [[buffer(4)]],           \
    constant uint3             & sizes          [[buffer(5)]],           \
    uint2                        thread_index [[thread_position_in_grid]])

INSTANTIATE_INT6MM(float, 32);
INSTANTIATE_INT6MM(half, 32);
INSTANTIATE_INT6MM(float, 64);
INSTANTIATE_INT6MM(half, 64);
INSTANTIATE_INT6MM(float, 128);
INSTANTIATE_INT6MM(half, 128);
INSTANTIATE_INT6MM(float, 256);
INSTANTIATE_INT6MM(half, 256);
#if __METAL_VERSION__ >= 310
INSTANTIATE_INT6MM(bfloat, 32);
INSTANTIATE_INT6MM(bfloat, 64);
INSTANTIATE_INT6MM(bfloat, 128);
INSTANTIATE_INT6MM(bfloat, 256);
#endif