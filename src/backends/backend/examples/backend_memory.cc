// Copyright (c) 2020, NVIDIA CORPORATION. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
//  * Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
//  * Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
//  * Neither the name of NVIDIA CORPORATION nor the names of its
//    contributors may be used to endorse or promote products derived
//    from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
// CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
// EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
// PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
// OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#include "src/backends/backend/examples/backend_memory.h"

#include "src/backends/backend/examples/backend_utils.h"

namespace triton { namespace backend {

TRITONSERVER_Error*
BackendMemory::Create(
    TRITONBACKEND_MemoryManager* manager,
    const TRITONSERVER_MemoryType memory_type, const int64_t memory_type_id,
    const size_t byte_size, BackendMemory** mem)
{
  *mem = nullptr;

  void* ptr = nullptr;
  RETURN_IF_ERROR(TRITONBACKEND_MemoryManagerAllocate(
      manager, &ptr, memory_type, memory_type_id, byte_size));

  *mem = new BackendMemory(
      manager, memory_type, memory_type_id, reinterpret_cast<char*>(ptr),
      byte_size);

  return nullptr;  // success
}

TRITONSERVER_Error*
BackendMemory::CreateWithFallback(
    TRITONBACKEND_MemoryManager* manager,
    const TRITONSERVER_MemoryType preferred_memory_type,
    const int64_t memory_type_id, const size_t byte_size, BackendMemory** mem)
{
  *mem = nullptr;

  TRITONSERVER_MemoryType memory_type = preferred_memory_type;
  void* ptr = nullptr;
  TRITONSERVER_Error* err = TRITONBACKEND_MemoryManagerAllocate(
      manager, &ptr, memory_type, memory_type_id, byte_size);
  if (err != nullptr) {
    TRITONSERVER_ErrorDelete(err);

    // Fallback to CPU memory...
    memory_type = TRITONSERVER_MEMORY_CPU;
    RETURN_IF_ERROR(TRITONBACKEND_MemoryManagerAllocate(
        manager, &ptr, memory_type, 0 /* memory_type_id */, byte_size));
  }

  *mem = new BackendMemory(
      manager, memory_type, memory_type_id, reinterpret_cast<char*>(ptr),
      byte_size);

  return nullptr;  // success
}

BackendMemory::~BackendMemory()
{
  LOG_IF_ERROR(
      TRITONBACKEND_MemoryManagerFree(manager_, buffer_, memtype_, memtype_id_),
      "failed to free memory buffer");
}

}}  // namespace triton::backend
