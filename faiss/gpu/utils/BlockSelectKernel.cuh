/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#pragma once

#include <faiss/gpu/utils/Select.cuh>

namespace faiss {
namespace gpu {

template <
        typename K,
        typename IndexType,
        bool Dir,
        int NumWarpQ,
        int NumThreadQ,
        int ThreadsPerBlock>
__global__ void blockSelect(
        Tensor<K, 2, true> in,
        Tensor<K, 2, true> outK,
        Tensor<IndexType, 2, true> outV,
        K initK,
        IndexType initV,
        int k) {
    if constexpr ((NumWarpQ == 1 && NumThreadQ == 1) || NumWarpQ >= kWarpSize) {
        constexpr int kNumWarps = ThreadsPerBlock / kWarpSize;

        __shared__ K smemK[kNumWarps * NumWarpQ];
        __shared__ IndexType smemV[kNumWarps * NumWarpQ];

        BlockSelect<
                K,
                IndexType,
                Dir,
                Comparator<K>,
                NumWarpQ,
                NumThreadQ,
                ThreadsPerBlock>
                heap(initK, initV, smemK, smemV, k);

        // Grid is exactly sized to rows available
        idx_t row = blockIdx.x;

        idx_t i = threadIdx.x;
        K* inStart = in[row][i].data();

        // Whole warps must participate in the selection
        idx_t limit = utils::roundDown(in.getSize(1), kWarpSize);

        for (; i < limit; i += ThreadsPerBlock) {
            heap.add(*inStart, (IndexType)i);
            inStart += ThreadsPerBlock;
        }

        // Handle last remainder fraction of a warp of elements
        if (i < in.getSize(1)) {
            heap.addThreadQ(*inStart, (IndexType)i);
        }

        heap.reduce();

        for (int i = threadIdx.x; i < k; i += ThreadsPerBlock) {
            outK[row][i] = smemK[i];
            outV[row][i] = smemV[i];
        }
    }
}

template <
        typename K,
        typename IndexType,
        bool Dir,
        int NumWarpQ,
        int NumThreadQ,
        int ThreadsPerBlock>
__global__ void blockSelectPair(
        Tensor<K, 2, true> inK,
        Tensor<IndexType, 2, true> inV,
        Tensor<K, 2, true> outK,
        Tensor<IndexType, 2, true> outV,
        K initK,
        IndexType initV,
        int k) {
    if constexpr ((NumWarpQ == 1 && NumThreadQ == 1) || NumWarpQ >= kWarpSize) {
        constexpr int kNumWarps = ThreadsPerBlock / kWarpSize;

        __shared__ K smemK[kNumWarps * NumWarpQ];
        __shared__ IndexType smemV[kNumWarps * NumWarpQ];

        BlockSelect<
                K,
                IndexType,
                Dir,
                Comparator<K>,
                NumWarpQ,
                NumThreadQ,
                ThreadsPerBlock>
                heap(initK, initV, smemK, smemV, k);

        // Grid is exactly sized to rows available
        idx_t row = blockIdx.x;

        idx_t i = threadIdx.x;
        K* inKStart = inK[row][i].data();
        IndexType* inVStart = inV[row][i].data();

        // Whole warps must participate in the selection
        idx_t limit = utils::roundDown(inK.getSize(1), (idx_t)kWarpSize);

        for (; i < limit; i += ThreadsPerBlock) {
            heap.add(*inKStart, *inVStart);
            inKStart += ThreadsPerBlock;
            inVStart += ThreadsPerBlock;
        }

        // Handle last remainder fraction of a warp of elements
        if (i < inK.getSize(1)) {
            heap.addThreadQ(*inKStart, *inVStart);
        }

        heap.reduce();

        for (int i = threadIdx.x; i < k; i += ThreadsPerBlock) {
            outK[row][i] = smemK[i];
            outV[row][i] = smemV[i];
        }
    }
}

void runBlockSelect(
        Tensor<float, 2, true>& in,
        Tensor<float, 2, true>& outKeys,
        Tensor<idx_t, 2, true>& outIndices,
        bool dir,
        int k,
        cudaStream_t stream);

void runBlockSelectPair(
        Tensor<float, 2, true>& inKeys,
        Tensor<idx_t, 2, true>& inIndices,
        Tensor<float, 2, true>& outKeys,
        Tensor<idx_t, 2, true>& outIndices,
        bool dir,
        int k,
        cudaStream_t stream);

void runBlockSelect(
        Tensor<half, 2, true>& in,
        Tensor<half, 2, true>& outKeys,
        Tensor<idx_t, 2, true>& outIndices,
        bool dir,
        int k,
        cudaStream_t stream);

void runBlockSelectPair(
        Tensor<half, 2, true>& inKeys,
        Tensor<idx_t, 2, true>& inIndices,
        Tensor<half, 2, true>& outKeys,
        Tensor<idx_t, 2, true>& outIndices,
        bool dir,
        int k,
        cudaStream_t stream);

} // namespace gpu
} // namespace faiss
