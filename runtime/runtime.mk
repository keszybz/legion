# Copyright 2019 Stanford University, NVIDIA Corporation
# Copyright 2019 Los Alamos National Laboratory 
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

USE_OPENMP ?= 0
BOUNDS_CHECKS ?= 0
ifeq ($(shell uname -s),Darwin)
DARWIN = 1
CC_FLAGS += -DDARWIN
ifeq ($(strip $(USE_OPENMP)),1)
$(warning "Some versions of Clang on Mac OSX do not support OpenMP")
endif
else
#use disk unless on DARWIN 
CC_FLAGS += -DUSE_DISK 
endif

ifndef LG_RT_DIR
$(error LG_RT_DIR variable is not defined, aborting build)
endif

# generate libraries for Legion and Realm
SLIB_LEGION     := liblegion.a
SLIB_REALM      := librealm.a
LEGION_LIBS     := -L. -llegion -lrealm

# Handle some of the common machines we frequent

ifeq ($(shell uname -n),sapling)
CONDUIT ?= ibv
GPU_ARCH ?= fermi
endif
ifeq ($(shell uname -n),n0000)
CONDUIT ?= ibv
GPU_ARCH ?= fermi
endif
ifeq ($(shell uname -n),n0001)
CONDUIT ?= ibv
GPU_ARCH ?= fermi
endif
ifeq ($(shell uname -n),n0002)
CONDUIT ?= ibv
GPU_ARCH ?= fermi
endif
ifeq ($(shell uname -n),n0003)
CONDUIT ?= ibv
GPU_ARCH ?= fermi
endif
ifeq ($(findstring xs,$(shell uname -n)), xs)
GPU_ARCH ?= k80
GASNET ?= /home/stanford/aaiken/users/zhihao/tools/gasnet/release/
CONDUIT ?= ibv #not sure if this is true
endif
ifeq ($(findstring nics.utk.edu,$(shell uname -n)),nics.utk.edu)
GASNET ?= /nics/d/home/sequoia/gasnet-1.20.2-openmpi
MPI=/sw/kfs/openmpi/1.6.1/centos6.2_intel2011_sp1.11.339
CUDA ?= /sw/kfs/cuda/4.2/linux_binary
CONDUIT ?= ibv
GPU_ARCH ?= fermi
endif
ifeq ($(findstring titan,$(shell uname -n)),titan)
# without this, lapack stuff will link, but generate garbage output - thanks Cray!
LAPACK_LIBS=-L/opt/acml/5.3.1/gfortran64_fma4/lib -Wl,-rpath=/opt/acml/5.3.1/gfortran64_fma4/lib -lacml
MARCH ?= bdver1
CONDUIT ?= gemini
GPU_ARCH ?= k20
endif
ifeq ($(findstring daint,$(shell uname -n)),daint)
CONDUIT ?= aries
GPU_ARCH ?= pascal
endif
ifeq ($(findstring excalibur,$(shell uname -n)),excalibur)
CONDUIT ?= aries
endif
ifeq ($(findstring cori,$(shell uname -n)),cori)
CONDUIT ?= aries
endif
ifeq ($(findstring sh,$(shell uname -n)), sh)
GPU_ARCH ?= pascal
CONDUIT ?= ibv #not sure if this is true
endif

# defaults for GASNet
CONDUIT ?= udp
ifdef GASNET_ROOT
GASNET ?= $(GASNET_ROOT)
endif

# defaults for CUDA
#GPU_ARCH ?= fermi
GPU_ARCH ?= kepler
#GPU_ARCH ?= k20
#GPU_ARCH ?= pascal
#GPU_ARCH ?= volta
#GPU_ARCH ?= turing

# if CUDA is not set, but CUDATOOLKIT_HOME or CUDA_HOME is, use that
ifdef CUDATOOLKIT_HOME
CUDA ?= $(CUDATOOLKIT_HOME)
endif
ifdef CUDA_HOME
CUDA ?= $(CUDA_HOME)
endif

# Customization specific to Cray programming environment
ifneq (${CRAYPE_VERSION},)
CXX=CC
F90=ftn
# Cray's magic wrappers automatically provide LAPACK goodness?
LAPACK_LIBS ?=
LEGION_LD_FLAGS += ${CRAY_UGNI_POST_LINK_OPTS}
LEGION_LD_FLAGS += ${CRAY_UDREG_POST_LINK_OPTS}
LEGION_LD_FLAGS += ${CRAY_PMI_POST_LINK_OPTS}
endif

# machine architecture (generally "native" unless cross-compiling)
MARCH ?= native

ifneq (${MARCH},)
  # Summit/Summitdev are strange and want to have this specified via -mcpu
  # instead of -march. Unclear if this is true in general for PPC.
  ifeq ($(findstring ppc64le,$(shell uname -p)),ppc64le)
    CC_FLAGS += -mcpu=${MARCH} -maltivec -mabi=altivec -mvsx
  else
    CC_FLAGS += -march=${MARCH}
  endif
endif

INC_FLAGS	+= -I$(LG_RT_DIR) -I$(LG_RT_DIR)/mappers
# support libraries are OS specific unfortunately
ifeq ($(shell uname -s),Linux)
LEGION_LD_FLAGS	+= -lrt -lpthread
endif
ifeq ($(shell uname -s),Darwin)
LEGION_LD_FLAGS	+= -lpthread
endif
ifeq ($(shell uname -s),FreeBSD)
LEGION_LD_FLAGS	+= -lexecinfo -lpthread
endif

ifeq ($(strip $(USE_HWLOC)),1)
  ifndef HWLOC 
    $(error HWLOC variable is not defined, aborting build)
  endif
  CC_FLAGS        += -DREALM_USE_HWLOC
  INC_FLAGS   += -I$(HWLOC)/include
  LEGION_LD_FLAGS += -L$(HWLOC)/lib -lhwloc
endif

ifeq ($(strip $(USE_PAPI)),1)
  ifndef PAPI_ROOT
    ifdef PAPI
      PAPI_ROOT = $(PAPI)
    else
      $(error USE_PAPI set, but neither PAPI nor PAPI_ROOT is defined, aborting build)
    endif
  endif
  CC_FLAGS        += -DREALM_USE_PAPI
  INC_FLAGS   += -I$(PAPI_ROOT)/include
  LEGION_LD_FLAGS += -L$(PAPI_ROOT)/lib -lpapi
endif

USE_LIBDL ?= 1
ifeq ($(strip $(USE_LIBDL)),1)
CC_FLAGS += -DUSE_LIBDL
ifneq ($(shell uname -s),Darwin)
#CC_FLAGS += -rdynamic
# FreeBSD doesn't actually have a separate libdl
ifneq ($(shell uname -s),FreeBSD)
LEGION_LD_FLAGS += -ldl
endif
LEGION_LD_FLAGS += -rdynamic
else
LEGION_LD_FLAGS += -ldl -Wl,-export_dynamic
endif
endif

USE_LLVM ?= 0
ifeq ($(strip $(USE_LLVM)),1)
  # prefer known-working versions, if they can be named explicitly
  LLVM_CONFIG ?= $(shell which llvm-config-3.9 llvm-config-3.8 llvm-config-3.6 llvm-config-3.5 llvm-config-4.0 llvm-config-5.0 llvm-config | head -1)
  ifeq ($(LLVM_CONFIG),)
    $(error cannot find llvm-config-* - set with LLVM_CONFIG if not in path)
  endif
  LLVM_VERSION_NUMBER := $(shell $(LLVM_CONFIG) --version | cut -c1,3)
  CC_FLAGS += -DREALM_USE_LLVM -DREALM_LLVM_VERSION=$(LLVM_VERSION_NUMBER)
  # NOTE: do not use these for all source files - just the ones that include llvm include files
  LLVM_CXXFLAGS ?= -std=c++11 -I$(shell $(LLVM_CONFIG) --includedir)
  ifeq ($(LLVM_VERSION_NUMBER),35)
    LLVM_LIBS += $(shell $(LLVM_CONFIG) --ldflags --libs irreader jit mcjit x86)
  else
    LLVM_LIBS += $(shell $(LLVM_CONFIG) --ldflags --libs irreader mcjit x86)
  endif
  # llvm-config --system-libs gives you all the libraries you might need for anything,
  #  which includes things we don't need, and might not be installed
  # by default, filter out libedit
  LLVM_SYSTEM_LIBS ?= $(filter-out -ledit,$(shell $(LLVM_CONFIG) --system-libs))
  LEGION_LD_FLAGS += $(LLVM_LIBS) $(LLVM_SYSTEM_LIBS)
endif

OMP_FLAGS ?=
ifeq ($(strip $(USE_OPENMP)),1)
  CC_FLAGS += -DREALM_USE_OPENMP
  # Add the -fopenmp flag for Linux, but not for Mac as clang doesn't need it
  #ifneq ($(strip $(DARWIN)),1)
  OMP_FLAGS += -fopenmp 
  #endif
  REALM_OPENMP_GOMP_SUPPORT ?= 1
  ifeq ($(strip $(REALM_OPENMP_GOMP_SUPPORT)),1)
    CC_FLAGS += -DREALM_OPENMP_GOMP_SUPPORT
  endif
  REALM_OPENMP_KMP_SUPPORT ?= 1	
  ifeq ($(strip $(REALM_OPENMP_KMP_SUPPORT)),1)
    CC_FLAGS += -DREALM_OPENMP_KMP_SUPPORT
  endif
endif

USE_PYTHON ?= 0
ifeq ($(strip $(USE_PYTHON)),1)
  ifneq ($(strip $(USE_LIBDL)),1)
    $(error USE_PYTHON requires USE_LIBDL)
  endif

  # Attempt to auto-detect location of Python shared library based on
  # the location of Python executable on PATH. We do this because the
  # shared library may not be on LD_LIBRARY_PATH even when the
  # executable is on PATH.

  # Note: Set PYTHON_ROOT to an empty string to skip this logic and
  # defer to the normal search of LD_LIBRARY_PATH instead. Or set
  # PYTHON_LIB to specify the path to the shared library directly.
  ifndef PYTHON_LIB
    ifndef PYTHON_ROOT
      PYTHON_EXE := $(shell which python)
      ifeq ($(PYTHON_EXE),)
        $(error cannot find python - set PYTHON_ROOT if not in PATH)
      endif
      PYTHON_VERSION_MAJOR := $(shell $(PYTHON_EXE) -c 'import sys; print(sys.version_info.major)')
      PYTHON_VERSION_MINOR := $(shell $(PYTHON_EXE) -c 'import sys; print(sys.version_info.minor)')
      PYTHON_ROOT := $(dir $(PYTHON_EXE))
    endif

    # Try searching for common locations of the Python shared library.
    ifneq ($(strip $(PYTHON_ROOT)),)
      ifeq ($(strip $(DARWIN)),1)
        PYTHON_EXT := dylib
      else
	PYTHON_EXT := so
      endif
      PYTHON_LIB := $(wildcard $(PYTHON_ROOT)/libpython$(PYTHON_VERSION_MAJOR).$(PYTHON_VERSION_MINOR)*.$(PYTHON_EXT))
      ifeq ($(strip $(PYTHON_LIB)),)
        PYTHON_LIB := $(wildcard $(abspath $(PYTHON_ROOT)/../lib/libpython$(PYTHON_VERSION_MAJOR).$(PYTHON_VERSION_MINOR)*.$(PYTHON_EXT)))
        ifeq ($(strip $(PYTHON_LIB)),)
          $(warning cannot find libpython$(PYTHON_VERSION_MAJOR).$(PYTHON_VERSION_MINOR)*.$(PYTHON_EXT) - falling back to using LD_LIBRARY_PATH)
          PYTHON_LIB :=
        endif
      endif
    endif
  endif

  ifneq ($(strip $(PYTHON_LIB)),)
    ifndef FORCE_PYTHON
      ifeq ($(wildcard $(PYTHON_LIB)),)
        $(error cannot find libpython$(PYTHON_VERSION_MAJOR).$(PYTHON_VERSION_MINOR).$(PYTHON_EXT) - PYTHON_LIB set but file does not exist)
      else
        CC_FLAGS += -DREALM_PYTHON_LIB="\"$(PYTHON_LIB)\""
      endif
    else
      CC_FLAGS += -DREALM_PYTHON_LIB="\"$(PYTHON_LIB)\""
    endif
  endif

  ifndef PYTHON_VERSION_MAJOR
    $(error cannot auto-detect Python version - please set PYTHON_VERSION_MAJOR)
  else
    CC_FLAGS += -DREALM_PYTHON_VERSION_MAJOR=$(PYTHON_VERSION_MAJOR)
  endif

  CC_FLAGS += -DREALM_USE_PYTHON
endif

USE_DLMOPEN ?= 0
ifeq ($(strip $(USE_DLMOPEN)),1)
  ifneq ($(strip $(USE_LIBDL)),1)
    $(error USE_DLMOPEN requires USE_LIBDL)
  endif

  CC_FLAGS += -DREALM_USE_DLMOPEN
endif

# Flags for Realm

# Realm uses CUDA if requested
ifeq ($(strip $(CUDA)),)
  USE_CUDA ?= 0
  ifeq ($(strip $(USE_CUDA)),1)
    $(error CUDA variable is not defined, aborting build)
  endif
else
  USE_CUDA ?= 1
endif

# General CUDA variables
ifeq ($(strip $(USE_CUDA)),1)
# Latter is preferred, former is for backwards compatability
CC_FLAGS        += -DUSE_CUDA -DREALM_USE_CUDA -DLEGION_USE_CUDA
# Latter is preferred, former is for backwards compatability
NVCC_FLAGS      += -DUSE_CUDA -DREALM_USE_CUDA -DLEGION_USE_CUDA
INC_FLAGS	+= -I$(CUDA)/include -I$(LG_RT_DIR)/realm/transfer
ifeq ($(strip $(DEBUG)),1)
NVCC_FLAGS	+= -DDEBUG_REALM -DDEBUG_LEGION -g -O0
#NVCC_FLAGS	+= -G
else
NVCC_FLAGS	+= -O2
endif
ifeq ($(strip $(DARWIN)),1)
LEGION_LD_FLAGS	+= -L$(CUDA)/lib -lcuda
else
LEGION_LD_FLAGS	+= -L$(CUDA)/lib64 -L$(CUDA)/lib64/stubs -lcuda -Xlinker -rpath=$(CUDA)/lib64
endif
# CUDA arch variables
ifeq ($(strip $(GPU_ARCH)),fermi)
NVCC_FLAGS	+= -arch=compute_20 -code=sm_20
NVCC_FLAGS	+= -DFERMI_ARCH
endif
ifeq ($(strip $(GPU_ARCH)),kepler)
NVCC_FLAGS	+= -arch=compute_30 -code=sm_30
NVCC_FLAGS	+= -DKEPLER_ARCH
endif
ifeq ($(strip $(GPU_ARCH)),k20)
NVCC_FLAGS	+= -arch=compute_35 -code=sm_35
NVCC_FLAGS	+= -DK20_ARCH
endif
ifeq ($(strip $(GPU_ARCH)),k80)
NVCC_FLAGS	+= -arch=compute_37 -code=sm_37
NVCC_FLAGS	+= -DK80_ARCH
endif
ifeq ($(strip $(GPU_ARCH)),maxwell)
NVCC_FLAGS	+= -arch=compute_52 -code=sm_52
NVCC_FLAGS	+= -DMAXWELL_ARCH
endif
ifeq ($(strip $(GPU_ARCH)),pascal)
NVCC_FLAGS	+= -arch=compute_60 -code=sm_60
NVCC_FLAGS	+= -DPASCAL_ARCH
endif
ifeq ($(strip $(GPU_ARCH)),volta)
NVCC_FLAGS	+= -arch=compute_70 -code=sm_70
NVCC_FLAGS	+= -DVOLTA_ARCH
endif
ifeq ($(strip $(GPU_ARCH)),turing)
NVCC_FLAGS	+= -arch=compute_75 -code=sm_75
NVCC_FLAGS	+= -DTURING_ARCH
endif
NVCC_FLAGS	+= -Xptxas "-v" #-abi=no"
endif

# Realm uses GASNet if requested
ifeq ($(strip $(GASNET)),)
  USE_GASNET ?= 0
  ifeq ($(strip $(USE_GASNET)),1)
    $(error GASNET variable is not defined, aborting build)
  endif
else
  USE_GASNET ?= 1
endif

ifeq ($(strip $(USE_GASNET)),1)
  # General GASNET variables
  INC_FLAGS	+= -I$(GASNET)/include
  ifeq ($(strip $(DARWIN)),1)
    LEGION_LD_FLAGS	+= -L$(GASNET)/lib -lm
  else
    LEGION_LD_FLAGS	+= -L$(GASNET)/lib -lrt -lm
  endif
  CC_FLAGS	+= -DUSE_GASNET
  # newer versions of gasnet seem to need this
  CC_FLAGS	+= -DGASNETI_BUG1389_WORKAROUND=1

  # GASNET conduit variables
  ifeq ($(strip $(CONDUIT)),ibv)
    INC_FLAGS 	+= -I$(GASNET)/include/ibv-conduit
    CC_FLAGS	+= -DGASNET_CONDUIT_IBV
    LEGION_LD_FLAGS	+= -lgasnet-ibv-par -libverbs
    # GASNet needs MPI for interop support
    USE_MPI	= 1
  endif
  ifeq ($(strip $(CONDUIT)),gemini)
    INC_FLAGS	+= -I$(GASNET)/include/gemini-conduit
    CC_FLAGS	+= -DGASNET_CONDUIT_GEMINI
    LEGION_LD_FLAGS	+= -lgasnet-gemini-par -lugni -ludreg -lpmi -lhugetlbfs
    # GASNet needs MPI for interop support
    USE_MPI	= 1
  endif
  ifeq ($(strip $(CONDUIT)),aries)
    INC_FLAGS   += -I$(GASNET)/include/aries-conduit
    CC_FLAGS    += -DGASNET_CONDUIT_ARIES
    LEGION_LD_FLAGS    += -lgasnet-aries-par -lugni -ludreg -lpmi -lhugetlbfs
    # GASNet needs MPI for interop support
    USE_MPI	= 1
  endif
  ifeq ($(strip $(CONDUIT)),psm)
    INC_FLAGS 	+= -I$(GASNET)/include/psm-conduit
    CC_FLAGS	+= -DGASNET_CONDUIT_PSM
    LEGION_LD_FLAGS	+= -lgasnet-psm-par -lpsm2 -lpmi2 # PMI2 is required for OpenMPI
    # GASNet needs MPI for interop support
    USE_MPI	= 1
  endif
  ifeq ($(strip $(CONDUIT)),mpi)
    INC_FLAGS	+= -I$(GASNET)/include/mpi-conduit
    CC_FLAGS	+= -DGASNET_CONDUIT_MPI
    LEGION_LD_FLAGS	+= -lgasnet-mpi-par -lammpi -lmpi
    USE_MPI	= 1
  endif
  ifeq ($(strip $(CONDUIT)),udp)
    INC_FLAGS	+= -I$(GASNET)/include/udp-conduit
    CC_FLAGS	+= -DGASNET_CONDUIT_UDP
    LEGION_LD_FLAGS	+= -lgasnet-udp-par -lamudp
  endif

endif

# Realm doesn't use HDF by default
USE_HDF ?= 0
HDF_LIBNAME ?= hdf5
ifeq ($(strip $(USE_HDF)), 1)
  CC_FLAGS      += -DUSE_HDF
  LEGION_LD_FLAGS      += -l$(HDF_LIBNAME)
  ifdef HDF_ROOT
       CC_FLAGS    += -I$(HDF_ROOT)/include
       LD_FLAGS    += -L$(HDF_ROOT)/lib
  else
    CC_FLAGS      += -I/usr/include/hdf5/serial
  endif
endif

SKIP_MACHINES= titan% daint% excalibur% cori%
#Extra options for MPI support in GASNet
ifeq ($(strip $(USE_MPI)),1)
  # Skip any machines on this list list
  ifeq ($(filter-out $(SKIP_MACHINES),$(shell uname -n)),$(shell uname -n))
    CC		:= mpicc
    CXX		:= mpicxx
    F90         := mpif90
    # Summit/Summitdev are strange and link this automatically (but still uses mpicxx).
    # FIXME: Unfortunately you can't match against the Summit hostname right now...
    ifneq ($(findstring ppc64le,$(shell uname -p)),ppc64le)
      LEGION_LD_FLAGS	+= -L$(MPI)/lib -lmpi
    endif
    LAPACK_LIBS ?= -lblas
  endif
endif


# libz
USE_ZLIB ?= 1
ZLIB_LIBNAME ?= z
ifeq ($(strip $(USE_ZLIB)),1)
  CC_FLAGS      += -DUSE_ZLIB
  LEGION_LD_FLAGS += -l$(ZLIB_LIBNAME)
endif


ifeq ($(strip $(DEBUG)),1)
CC_FLAGS	+= -DDEBUG_REALM -DDEBUG_LEGION -O0 -ggdb #-ggdb -Wall
else
CC_FLAGS	+= -O2 -fno-strict-aliasing #-ggdb
endif

# DEBUG_TSAN=1 enables thread sanitizer (data race) checks
ifeq ($(strip $(DEBUG_TSAN)),1)
CC_FLAGS        += -fsanitize=thread -g -DTSAN_ENABLED
LD_FLAGS        += -fsanitize=thread
endif

# Set maximum number of dimensions
ifneq ($(strip ${MAX_DIM}),)
CC_FLAGS	+= -DREALM_MAX_DIM=$(MAX_DIM) -DLEGION_MAX_DIM=$(MAX_DIM)
NVCC_FLAGS	+= -DREALM_MAX_DIM=$(MAX_DIM) -DLEGION_MAX_DIM=$(MAX_DIM)
endif

# Manage the output setting
CC_FLAGS	+= -DCOMPILE_TIME_MIN_LEVEL=$(OUTPUT_LEVEL)

# demand warning-free compilation
CC_FLAGS        += -Wall -Wno-strict-overflow
ifeq ($(strip $(WARN_AS_ERROR)),1)
CC_FLAGS        += -Werror
endif

#CC_FLAGS += -DUSE_MASKED_COPIES

REALM_SRC	?=
LEGION_SRC	?=
GPU_RUNTIME_SRC	?=
MAPPER_SRC	?=
ASM_SRC		?=

# Set the source files
REALM_SRC 	+= $(LG_RT_DIR)/realm/runtime_impl.cc \
	           $(LG_RT_DIR)/realm/transfer/transfer.cc \
	           $(LG_RT_DIR)/realm/transfer/channel.cc \
	           $(LG_RT_DIR)/realm/transfer/channel_disk.cc \
	           $(LG_RT_DIR)/realm/transfer/lowlevel_dma.cc \
	           $(LG_RT_DIR)/realm/module.cc \
	           $(LG_RT_DIR)/realm/threads.cc \
	           $(LG_RT_DIR)/realm/faults.cc \
		   $(LG_RT_DIR)/realm/operation.cc \
	           $(LG_RT_DIR)/realm/tasks.cc \
	           $(LG_RT_DIR)/realm/metadata.cc \
	           $(LG_RT_DIR)/realm/deppart/partitions.cc \
	           $(LG_RT_DIR)/realm/deppart/sparsity_impl.cc \
	           $(LG_RT_DIR)/realm/deppart/image.cc \
	           $(LG_RT_DIR)/realm/deppart/preimage.cc \
	           $(LG_RT_DIR)/realm/deppart/byfield.cc \
	           $(LG_RT_DIR)/realm/deppart/setops.cc \
		   $(LG_RT_DIR)/realm/event_impl.cc \
		   $(LG_RT_DIR)/realm/rsrv_impl.cc \
		   $(LG_RT_DIR)/realm/proc_impl.cc \
		   $(LG_RT_DIR)/realm/mem_impl.cc \
		   $(LG_RT_DIR)/realm/inst_impl.cc \
		   $(LG_RT_DIR)/realm/inst_layout.cc \
		   $(LG_RT_DIR)/realm/machine_impl.cc \
		   $(LG_RT_DIR)/realm/sampling_impl.cc \
                   $(LG_RT_DIR)/realm/transfer/lowlevel_disk.cc
REALM_SRC 	+= $(LG_RT_DIR)/realm/numa/numa_module.cc \
		   $(LG_RT_DIR)/realm/numa/numasysif.cc
ifeq ($(strip $(USE_OPENMP)),1)
REALM_SRC 	+= $(LG_RT_DIR)/realm/openmp/openmp_module.cc \
		   $(LG_RT_DIR)/realm/openmp/openmp_threadpool.cc \
		   $(LG_RT_DIR)/realm/openmp/openmp_api.cc
endif
REALM_SRC 	+= $(LG_RT_DIR)/realm/procset/procset_module.cc
ifeq ($(strip $(USE_PYTHON)),1)
REALM_SRC 	+= $(LG_RT_DIR)/realm/python/python_module.cc \
		   $(LG_RT_DIR)/realm/python/python_source.cc
endif
ifeq ($(strip $(USE_CUDA)),1)
REALM_SRC 	+= $(LG_RT_DIR)/realm/cuda/cuda_module.cc \
		   $(LG_RT_DIR)/realm/cuda/cudart_hijack.cc
endif
ifeq ($(strip $(USE_LLVM)),1)
REALM_SRC 	+= $(LG_RT_DIR)/realm/llvmjit/llvmjit_module.cc \
                   $(LG_RT_DIR)/realm/llvmjit/llvmjit_internal.cc
endif
ifeq ($(strip $(USE_HDF)),1)
REALM_SRC 	+= $(LG_RT_DIR)/realm/hdf5/hdf5_module.cc \
		   $(LG_RT_DIR)/realm/hdf5/hdf5_internal.cc \
		   $(LG_RT_DIR)/realm/hdf5/hdf5_access.cc
endif
REALM_SRC 	+= $(LG_RT_DIR)/realm/activemsg.cc
GPU_RUNTIME_SRC +=

REALM_SRC 	+= $(LG_RT_DIR)/realm/logging.cc \
	           $(LG_RT_DIR)/realm/cmdline.cc \
		   $(LG_RT_DIR)/realm/profiling.cc \
	           $(LG_RT_DIR)/realm/codedesc.cc \
		   $(LG_RT_DIR)/realm/timers.cc

MAPPER_SRC	+= $(LG_RT_DIR)/mappers/default_mapper.cc \
		   $(LG_RT_DIR)/mappers/mapping_utilities.cc \
		   $(LG_RT_DIR)/mappers/shim_mapper.cc \
		   $(LG_RT_DIR)/mappers/test_mapper.cc \
		   $(LG_RT_DIR)/mappers/null_mapper.cc \
		   $(LG_RT_DIR)/mappers/replay_mapper.cc \
		   $(LG_RT_DIR)/mappers/debug_mapper.cc \
		   $(LG_RT_DIR)/mappers/wrapper_mapper.cc

LEGION_SRC 	+= $(LG_RT_DIR)/legion/legion.cc \
		    $(LG_RT_DIR)/legion/legion_c.cc \
		    $(LG_RT_DIR)/legion/legion_ops.cc \
		    $(LG_RT_DIR)/legion/legion_tasks.cc \
		    $(LG_RT_DIR)/legion/legion_context.cc \
		    $(LG_RT_DIR)/legion/legion_trace.cc \
		    $(LG_RT_DIR)/legion/legion_spy.cc \
		    $(LG_RT_DIR)/legion/legion_profiling.cc \
		    $(LG_RT_DIR)/legion/legion_profiling_serializer.cc \
		    $(LG_RT_DIR)/legion/legion_instances.cc \
		    $(LG_RT_DIR)/legion/legion_views.cc \
		    $(LG_RT_DIR)/legion/legion_analysis.cc \
		    $(LG_RT_DIR)/legion/legion_constraint.cc \
		    $(LG_RT_DIR)/legion/legion_mapping.cc \
		    $(LG_RT_DIR)/legion/region_tree.cc \
		    $(LG_RT_DIR)/legion/runtime.cc \
		    $(LG_RT_DIR)/legion/garbage_collection.cc \
		    $(LG_RT_DIR)/legion/mapper_manager.cc

# General shell commands
SHELL	:= /bin/sh
SH	:= sh
RM	:= rm
LS	:= ls
MKDIR	:= mkdir
MV	:= mv
CP	:= cp
SED	:= sed
ECHO	:= echo
TOUCH	:= touch
MAKE	:= make
ifndef NVCC
NVCC	:= $(CUDA)/bin/nvcc
endif
SSH	:= ssh
SCP	:= scp

GEN_OBJS	:= $(GEN_SRC:.cc=.cc.o)
REALM_OBJS	:= $(REALM_SRC:.cc=.cc.o)
LEGION_OBJS	:= $(LEGION_SRC:.cc=.cc.o)
MAPPER_OBJS	:= $(MAPPER_SRC:.cc=.cc.o)
ASM_OBJS	:= $(ASM_SRC:.S=.S.o)
# Only compile the gpu objects if we need to 
ifeq ($(strip $(USE_CUDA)),1)
GEN_GPU_OBJS	:= $(GEN_GPU_SRC:.cu=.cu.o)
GPU_RUNTIME_OBJS:= $(GPU_RUNTIME_SRC:.cu=.cu.o)
else
GEN_GPU_OBJS	:=
GPU_RUNTIME_OBJS:=
endif

# Provide build rules unless the user asks us not to
ifndef NO_BUILD_RULES
# Provide an all unless the user asks us not to
ifndef NO_BUILD_ALL
.PHONY: all
all: $(OUTFILE)
endif

# If we're using CUDA we have to link with nvcc
$(OUTFILE) : $(GEN_OBJS) $(GEN_GPU_OBJS) $(SLIB_LEGION) $(SLIB_REALM)
	@echo "---> Linking objects into one binary: $(OUTFILE)"
	$(CXX) -o $(OUTFILE) $(GEN_OBJS) $(GEN_GPU_OBJS) $(LD_FLAGS) $(LEGION_LIBS) $(LEGION_LD_FLAGS) $(GASNET_FLAGS)

$(SLIB_LEGION) : $(LEGION_OBJS) $(MAPPER_OBJS)
	rm -f $@
	$(AR) rc $@ $^

$(SLIB_REALM) : $(REALM_OBJS)
	rm -f $@
	$(AR) rc $@ $^

$(GEN_OBJS) : %.cc.o : %.cc #legion_defines.h realm_defines.h
	$(CXX) -o $@ -c $< $(CC_FLAGS) $(INC_FLAGS) $(OMP_FLAGS)

$(ASM_OBJS) : %.S.o : %.S
	$(CXX) -o $@ -c $< $(CC_FLAGS) $(INC_FLAGS)

$(REALM_OBJS) : %.cc.o : %.cc #legion_defines.h realm_defines.h
	$(CXX) -o $@ -c $< $(CC_FLAGS) $(INC_FLAGS)

$(LEGION_OBJS) : %.cc.o : %.cc #legion_defines.h realm_defines.h
	$(CXX) -o $@ -c $< $(CC_FLAGS) $(INC_FLAGS)

$(MAPPER_OBJS) : %.cc.o : %.cc #legion_defines.h realm_defines.h
	$(CXX) -o $@ -c $< $(CC_FLAGS) $(INC_FLAGS)

$(GEN_GPU_OBJS) : %.cu.o : %.cu #legion_defines.h realm_defines.h
	$(NVCC) -o $@ -c $< $(NVCC_FLAGS) $(INC_FLAGS)

$(GPU_RUNTIME_OBJS): %.cu.o : %.cu #legion_defines.h realm_defines.h
	$(NVCC) -o $@ -c $< $(NVCC_FLAGS) $(INC_FLAGS)

# disable gmake's default rule for building % from %.o
% : %.o

clean::
	$(RM) -f $(OUTFILE) $(SLIB_LEGION) $(SLIB_REALM) $(GEN_OBJS) $(GEN_GPU_OBJS) $(REALM_OBJS) $(LEGION_OBJS) $(GPU_RUNTIME_OBJS) $(MAPPER_OBJS) $(ASM_OBJS) legion_defines.h realm_defines.h

legion_defines.h : Makefile
	@echo "/**" > $@
	@echo " * \\\file legion_defines.h" >> $@
	@echo " * Public-facing definitions of variables configured at build time" >> $@
	@echo " */\n" >> $@
	@echo "// ******************** IMPORTANT **************************" >> $@
	@echo "//" >> $@
	@echo "// This file is PURE C, **NOT** C++. Keep any C++-isms in" >> $@
	@echo "// legion_types.h, or elsewhere." >> $@
	@echo "//" >> $@
	@echo "// ******************** IMPORTANT **************************\n" >> $@
	@echo "#ifndef DEBUG_LEGION" >> $@
ifeq ($(strip $(DEBUG)),1)
	@echo "#define DEBUG_LEGION" >> $@
else
	@echo "/* #undef DEBUG_LEGION */" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef PRIVILEGE_CHECKS" >> $@
ifeq ($(strip $(DEBUG)),1)
	@echo "#define PRIVILEGE_CHECKS" >> $@
else
	@echo "/* #undef PRIVILEGE_CHECKS */" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef BOUNDS_CHECKS" >> $@
ifeq ($(strip $(BOUNDS_CHECKS)),1)
	@echo "#define BOUNDS_CHECKS" >> $@
else
	@echo "/* #undef BOUNDS_CHECKS */" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef LEGION_MAX_DIM" >> $@
ifeq ($(strip ${MAX_DIM}),)
	@echo "#define LEGION_MAX_DIM 3" >> $@
else
	@echo "#define LEGION_MAX_DIM $(MAX_DIM)" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef MAX_FIELDS" >> $@
ifeq ($(strip ${MAX_FIELDS}),)
	@echo "#define MAX_FIELDS 512" >> $@
else
	@echo "#define MAX_FIELDS $(MAX_FIELDS)" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef ENABLE_LEGION_TLS" >> $@
	@echo "#define ENABLE_LEGION_TLS" >> $@
	@echo "#endif\n" >> $@
	@echo "#ifndef __STDC_FORMAT_MACROS" >> $@
	@echo "#define __STDC_FORMAT_MACROS" >> $@
	@echo "#endif\n" >> $@
	@echo "#ifndef LEGION_USE_CUDA" >> $@
ifeq ($(strip $(USE_CUDA)),1)
	@echo "#define LEGION_USE_CUDA" >> $@
else
	@echo "/* #undef LEGION_USE_CUDA */" >> $@
endif
	@echo "#endif" >> $@

realm_defines.h : Makefile
	@echo "/**" > $@
	@echo " * \\\file realm_defines.h" >> $@
	@echo " * Public-facing definitions of variables configured at build time" >> $@
	@echo " */\n" >> $@
	@echo "// ******************** IMPORTANT **************************" >> $@
	@echo "//" >> $@
	@echo "// This file is PURE C, **NOT** C++. Keep any C++-isms in" >> $@
	@echo "// realm_config.h, or elsewhere." >> $@
	@echo "//" >> $@
	@echo "// ******************** IMPORTANT **************************\n" >> $@
	@echo "#ifndef DEBUG_REALM" >> $@
ifeq ($(strip $(DEBUG)),1)
	@echo "#define DEBUG_REALM" >> $@
else
	@echo "/* #undef DEBUG_REALM*/" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef COMPILE_TIME_MIN_LEVEL" >> $@
	@echo "#define COMPILE_TIME_MIN_LEVEL $(OUTPUT_LEVEL)" >> $@
	@echo "#endif\n" >> $@
	@echo "#ifndef REALM_MAX_DIM" >> $@
ifeq ($(strip ${MAX_DIM}),)
	@echo "#define REALM_MAX_DIM 3" >> $@
else
	@echo "#define REALM_MAX_DIM $(MAX_DIM)" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef REALM_USE_OPENMP" >> $@
ifeq ($(strip $(USE_OPENMP)),1)
	@echo "#define REALM_USE_OPENMP" >> $@
else
	@echo "/* #undef REALM_USE_OPENMP */" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef REALM_OPENMP_GOMP_SUPPORT" >> $@
ifeq ($(strip $(USE_OPENMP)),1)
	@echo "#define REALM_OPENMP_GOMP_SUPPORT" >> $@
else
	@echo "/* #undef REALM_OPENMP_GOMP_SUPPORT*/" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef REALM_OPENMP_KMP_SUPPORT" >> $@
ifeq ($(strip $(USE_OPENMP)),1)
	@echo "#define REALM_OPENMP_KMP_SUPPORT" >> $@
else
	@echo "/* #undef REALM_OPENMP_KMP_SUPPORT*/" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef REALM_USE_PYTHON" >> $@
ifeq ($(strip ${USE_PYTHON}),)
	@echo "#define REALM_USE_PYTHON" >> $@
else
	@echo "/* #undef REALM_USE_PYTHON */" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef REALM_PYTHON_VERSION_MAJOR" >> $@
ifeq ($(strip ${USE_PYTHON}),)
	@echo "#define REALM_PYTHON_VERSION_MAJOR $(PYTHON_VERSION_MAJOR)" >> $@
else
	@echo "/* #undef REALM_PYTHON_VERSION_MAJOR */" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef REALM_USE_CUDA" >> $@
ifeq ($(strip $(USE_CUDA)),1)
	@echo "#define REALM_USE_CUDA" >> $@
else
	@echo "/* #undef REALM_USE_CUDA */" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef USE_CUDA" >> $@
ifeq ($(strip $(USE_CUDA)),1)
	@echo "#define USE_CUDA" >> $@
else
	@echo "/* #undef USE_CUDA */" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef USE_GASNET" >> $@
ifeq ($(strip $(USE_GASNET)),1)
	@echo "#define USE_GASNET" >> $@
else
	@echo "/* #undef USE_GASNET */" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef GASNET_CONDUIT_MPI" >> $@
ifeq ($(strip $(USE_GASNET)),1)
ifeq ($(strip $(CONDUIT)),mpi)
	@echo "#define GASNET_CONDUIT_MPI" >> $@
else
	@echo "/* #undef GASNET_CONDUIT_MPI */" >> $@
endif
else
	@echo "/* #undef GASNET_CONDUIT_MPI */" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef GASNET_CONDUIT_IBV" >> $@
ifeq ($(strip $(USE_GASNET)),1)
ifeq ($(strip $(CONDUIT)),ibv)
	@echo "#define GASNET_CONDUIT_IBV" >> $@
else
	@echo "/* #undef GASNET_CONDUIT_IBV */" >> $@
endif
else
	@echo "/* #undef GASNET_CONDUIT_IBV */" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef GASNET_CONDUIT_UDP" >> $@
ifeq ($(strip $(USE_GASNET)),1)
ifeq ($(strip $(CONDUIT)),udp)
	@echo "#define GASNET_CONDUIT_UDP" >> $@
else
	@echo "/* #undef GASNET_CONDUIT_UDP */" >> $@
endif
else
	@echo "/* #undef GASNET_CONDUIT_UDP */" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef GASNET_CONDUIT_ARIES" >> $@
ifeq ($(strip $(USE_GASNET)),1)
ifeq ($(strip $(CONDUIT)),aries)
	@echo "#define GASNET_CONDUIT_ARIES" >> $@
else
	@echo "/* #undef GASNET_CONDUIT_ARIES */" >> $@
endif
else
	@echo "/* #undef GASNET_CONDUIT_ARIES */" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef GASNET_CONDUIT_GEMINI" >> $@
ifeq ($(strip $(USE_GASNET)),1)
ifeq ($(strip $(CONDUIT)),gemini)
	@echo "#define GASNET_CONDUIT_GEMINI" >> $@
else
	@echo "/* #undef GASNET_CONDUIT_GEMINI */" >> $@
endif
else
	@echo "/* #undef GASNET_CONDUIT_GEMINI */" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef GASNET_CONDUIT_PSM" >> $@
ifeq ($(strip $(USE_GASNET)),1)
ifeq ($(strip $(CONDUIT)),psm)
	@echo "#define GASNET_CONDUIT_PSM" >> $@
else
	@echo "/* #undef GASNET_CONDUIT_PSM */" >> $@
endif
else
	@echo "/* #undef GASNET_CONDUIT_PSM */" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef GASNETI_BUG1389_WORKAROUND" >> $@
	@echo "#define GASNETI_BUG1389_WORKAROUND 1" >> $@
	@echo "#endif\n" >> $@
	@echo "#ifndef REALM_USE_LLVM" >> $@
ifeq ($(strip $(USE_LLVM)),1)
	@echo "#define REALM_USE_LLVM" >> $@
else
	@echo "/* #undef REALM_USE_LLVM */" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef REALM_LLVM_VERSION" >> $@
ifeq ($(strip $(USE_LLVM)),1)
	@echo "#define REALM_LLVM_VERSION $(LLVM_VERSION_NUMBER)" >> $@
else
	@echo "/* #undef REALM_LLVM_VERSION */" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef REALM_ALLOW_MISSING_LLVM_LIBS" >> $@
ifeq ($(strip $(USE_LLVM)),1)
	@echo "#define REALM_ALLOW_MISSING_LLVM_LIBS" >> $@
else
	@echo "/* #undef REALM_ALLOW_MISSING_LLVM_LIBS */" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef USE_HDF" >> $@
ifeq ($(strip $(USE_HDF)),1)
	@echo "#define USE_HDF" >> $@
else
	@echo "/* #undef USE_HDF*/" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef USE_LIBDL" >> $@
ifeq ($(strip $(USE_LIBDL)),1)
	@echo "#define USE_LIBDL" >> $@
else
	@echo "/* #undef USE_LIBDL*/" >> $@
endif
	@echo "#endif\n" >> $@
	@echo "#ifndef __STDC_FORMAT_MACROS" >> $@
	@echo "#define __STDC_FORMAT_MACROS" >> $@
	@echo "#endif" >> $@

endif

ifeq ($(strip $(USE_LLVM)),1)
llvmjit_internal.cc.o : CC_FLAGS += $(LLVM_CXXFLAGS)
%/llvmjit_internal.cc.o : CC_FLAGS += $(LLVM_CXXFLAGS)
endif
