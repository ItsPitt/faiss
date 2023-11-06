/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include <faiss/IndexFlat.h>
#include <faiss/hip/GpuIndexFlat.h>
#include <faiss/hip/StandardGpuResources.h>
#include <faiss/hip/test/TestUtils.h>
#include <faiss/hip/utils/DeviceUtils.h>
#include <gtest/gtest.h>

// Test to see if we can recover after attempting to allocate too much GPU
// memory
TEST(TestGpuMemoryException, AddException) {
    size_t numBrokenAdd = std::numeric_limits<int>::max();
    size_t numRealAdd = 10000;
    size_t devFree = 0;
    size_t devTotal = 0;

    HIP_VERIFY(hipMemGetInfo(&devFree, &devTotal));

    // Figure out the dimensionality needed to get at least greater than
    // devTotal
    size_t brokenAddDims = ((devTotal / sizeof(float)) / numBrokenAdd) + 1;
    size_t realAddDims = 128;

    faiss::hip::StandardGpuResources res;

    faiss::hip::GpuIndexFlatConfig config;
    config.device = faiss::hip::randVal(0, faiss::hip::getNumDevices() - 1);

    faiss::hip::GpuIndexFlatL2 gpuIndexL2Broken(
            &res, (int)brokenAddDims, config);
    faiss::hip::GpuIndexFlatL2 gpuIndexL2(&res, (int)realAddDims, config);
    faiss::IndexFlatL2 cpuIndex((int)realAddDims);

    // Should throw on attempting to allocate too much data
    {
        // allocate memory without initialization
        auto vecs = std::unique_ptr<float[]>(
                new float[numBrokenAdd * brokenAddDims]);
        EXPECT_THROW(
                gpuIndexL2Broken.add(numBrokenAdd, vecs.get()),
                faiss::FaissException);
    }

    // Should be able to add a smaller set of data now
    {
        auto vecs = faiss::hip::randVecs(numRealAdd, realAddDims);
        EXPECT_NO_THROW(gpuIndexL2.add(numRealAdd, vecs.data()));
        cpuIndex.add(numRealAdd, vecs.data());
    }

    // Should throw on attempting to allocate too much data
    {
        // allocate memory without initialization
        auto vecs = std::unique_ptr<float[]>(
                new float[numBrokenAdd * brokenAddDims]);
        EXPECT_THROW(
                gpuIndexL2Broken.add(numBrokenAdd, vecs.get()),
                faiss::FaissException);
    }

    // Should be able to query results from what we had before
    {
        size_t numQuery = 10;
        auto vecs = faiss::hip::randVecs(numQuery, realAddDims);
        EXPECT_NO_THROW(compareIndices(
                vecs,
                cpuIndex,
                gpuIndexL2,
                numQuery,
                realAddDims,
                50,
                "",
                6e-3f,
                0.1f,
                0.015f));
    }
}

int main(int argc, char** argv) {
    testing::InitGoogleTest(&argc, argv);

    // just run with a fixed test seed
    faiss::hip::setTestSeed(100);

    return RUN_ALL_TESTS();
}
