# CUDA toolchain path
CUDA_DIR = /usr/local/cuda
CUDA_LIB_DIR := $(CUDA_DIR)/lib64
CC := $(CUDA_DIR)/bin/nvcc

# Target install directory
DESTDIR = /usr/local

# Build flags
CUDA_ARCH_FLAGS := \
    -arch=sm_60 \
    -gencode=arch=compute_60,code=sm_60 \
    -gencode=arch=compute_61,code=sm_61 \
    -gencode=arch=compute_70,code=sm_70 \
    -gencode=arch=compute_75,code=sm_75 \
	-gencode=arch=compute_80,code=sm_80

CC_FLAGS += $(CUDA_ARCH_FLAGS) -I. -O3 -Xcompiler -fPIC --default-stream per-thread
LD_FLAGS := -Xcompiler -fPIC -shared
IOFILTER_CFLAGS := $(shell pkg-config --cflags hdf5)
IOFILTER_LDFLAGS := $(shell pkg-config --libs hdf5) -lnvcomp

IOFILTER_SRC = nvcomp_iofilter.cu
IOFILTER_OBJ = $(patsubst %.cu,%.o,$(IOFILTER_SRC))
IOFILTER_LIB = lib$(patsubst %.cu,%.so,$(IOFILTER_SRC))

# Main targets
all: $(IOFILTER_LIB)

$(IOFILTER_LIB): $(IOFILTER_OBJ)
	$(CC) $^ $(CUDA_ARCH_FLAGS) $(IOFILTER_LDFLAGS) $(LD_FLAGS) -o $@

$(IOFILTER_OBJ): nvcomp_iofilter.cu nvcomp_iofilter.h
	$(CC) -c  $< $(CC_FLAGS) $(IOFILTER_CFLAGS)

install:
	@install -v -d $(DESTDIR)/bin $(DESTDIR)/lib $(DESTDIR)/include
	@install -v *.h $(DESTDIR)/include
	@if [ -e libnvcomp_iofilter.so ]; then \
		install -v -d $(DESTDIR)/hdf5/lib/plugin; \
		install -v libnvcomp_iofilter.so $(DESTDIR)/hdf5/lib/plugin; \
	fi

clean: 
	rm -f $(IOFILTER_LIB) $(IOFILTER_OBJ)
