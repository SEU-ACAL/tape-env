# Set one of USE_TSMC28_SRAM or USE_SMIC180_SRAM to compile top-level
# sequential memories with the corresponding hard SRAM macros.
USE_TSMC28_SRAM ?= 0
USE_SMIC180_SRAM ?= 0
USE_SMIC180_IO ?= 0
USE_SMIC180_STD ?= 0

# TapeoutConfig and TapeoutSimConfig are the supported physical SMIC180
# configurations.
SMIC180_TAPEOUT_CONFIGS ?= TapeoutConfig TapeoutSimConfig
ifneq ($(filter $(CONFIG),$(SMIC180_TAPEOUT_CONFIGS)),)
override USE_SMIC180_IO := 1
override USE_SMIC180_STD := 1
endif

TSMC28_SRAM_ROOT ?= /data2/TSMC28/Memory/SRAM
TSMC28_SRAM_MDF ?= $(base_dir)/generator/chipyard/vlsi/tsmc28_sram_library.mdf.json
TSMC28_SRAM_SIM_SOURCES ?= $(base_dir)/generator/chipyard/vlsi/tsmc28_sram_sim.sources
TSMC28_SRAM_SIM_FILELIST ?= $(build_dir)/tsmc28_sram_sim.f
TSMC28_SRAM_SIM_PREPROC_DEFINES ?= +define+UNIT_DELAY +define+no_warning
TSMC28_SRAM_CONFIG_STAMP ?= $(build_dir)/.tsmc28-sram-config.stamp

SMIC180_SRAM_ROOT ?= /data2/smic180/SRAM/S018SP_v0p1pc_CDK/SMIC180_S018SP_v0p1c_20260722
SMIC180_SRAM_MDF ?= $(base_dir)/generator/chipyard/vlsi/smic180_sram_library.mdf.json
SMIC180_SRAM_SIM_SOURCES ?= $(base_dir)/generator/chipyard/vlsi/smic180_sram_sim.sources
SMIC180_SRAM_SIM_FILELIST ?= $(build_dir)/smic180_sram_sim.f
SMIC180_SRAM_SIM_FLAGS ?= +notimingcheck
SMIC180_SRAM_CONFIG_STAMP ?= $(build_dir)/.smic180-sram-config.stamp

SMIC180_IO_ROOT ?= /data2/smic180/SP018RP_V1p0b
SMIC180_IO_SIM_SOURCES ?= $(base_dir)/generator/chipyard/vlsi/smic180_io_sim.sources
SMIC180_IO_SIM_FILELIST ?= $(build_dir)/smic180_io_sim.f
SMIC180_IO_SIM_PREPROC_DEFINES ?= +define+functional
SMIC180_IO_CONFIG_STAMP ?= $(build_dir)/.smic180-io-config.stamp

SMIC180_STD_ROOT ?= /data2/smic180/SCC018UG_UHD_RVT_V0.4a/SCC018UG_UHD_RVT_V0p4a
SMIC180_STD_SIM_FILELIST ?= $(build_dir)/smic180_std_sim.f
SMIC180_STD_SIM_PREPROC_DEFINES ?= +define+functional
SMIC180_STD_CONFIG_STAMP ?= $(build_dir)/.smic180-std-config.stamp

ifeq ($(USE_SMIC180_IO),1)
ifneq ($(SIM),vcs)
$(error SMIC180 SP018RP IO models require SIM=vcs; Verilator does not support the full PDK model)
endif
endif

ifeq ($(USE_SMIC180_STD),1)
ifneq ($(SIM),vcs)
$(error SMIC180 UHD standard-cell models require SIM=vcs; Verilator does not support the full PDK model)
endif
endif

TOP_MACRO_STAMP_DEPS += $(TSMC28_SRAM_CONFIG_STAMP) $(SMIC180_SRAM_CONFIG_STAMP)
SIM_CONFIG_STAMPS += $(TSMC28_SRAM_CONFIG_STAMP) $(SMIC180_SRAM_CONFIG_STAMP) $(SMIC180_STD_CONFIG_STAMP)

.PHONY: tsmc28-sram-config-force
tsmc28-sram-config-force:

$(TSMC28_SRAM_CONFIG_STAMP): tsmc28-sram-config-force
	mkdir -p $(dir $@)
	@{ \
		printf '%s\\n' 'USE_TSMC28_SRAM=$(USE_TSMC28_SRAM)'; \
		printf '%s\\n' 'TOP_MACROCOMPILER_MODE=$(TOP_MACROCOMPILER_MODE)'; \
		printf '%s\\n' 'TSMC28_SRAM_MDF=$(TSMC28_SRAM_MDF)'; \
		printf '%s\\n' 'TSMC28_SRAM_ROOT=$(TSMC28_SRAM_ROOT)'; \
		printf '%s\\n' 'TSMC28_SRAM_SIM_SOURCES=$(TSMC28_SRAM_SIM_SOURCES)'; \
		printf '%s\\n' 'TSMC28_SRAM_SIM_PREPROC_DEFINES=$(TSMC28_SRAM_SIM_PREPROC_DEFINES)'; \
	} > $@.tmp; \
	if ! cmp -s $@.tmp $@; then mv $@.tmp $@; else rm -f $@.tmp; fi

.PHONY: smic180-sram-config-force
smic180-sram-config-force:

$(SMIC180_SRAM_CONFIG_STAMP): smic180-sram-config-force
	mkdir -p $(dir $@)
	@{ \
		printf '%s\\n' 'USE_SMIC180_SRAM=$(USE_SMIC180_SRAM)'; \
		printf '%s\\n' 'TOP_MACROCOMPILER_MODE=$(TOP_MACROCOMPILER_MODE)'; \
		printf '%s\\n' 'SMIC180_SRAM_MDF=$(SMIC180_SRAM_MDF)'; \
		printf '%s\\n' 'SMIC180_SRAM_ROOT=$(SMIC180_SRAM_ROOT)'; \
		printf '%s\\n' 'SMIC180_SRAM_SIM_SOURCES=$(SMIC180_SRAM_SIM_SOURCES)'; \
		printf '%s\\n' 'SMIC180_SRAM_SIM_FLAGS=$(SMIC180_SRAM_SIM_FLAGS)'; \
	} > $@.tmp; \
	if ! cmp -s $@.tmp $@; then mv $@.tmp $@; else rm -f $@.tmp; fi

.PHONY: smic180-io-config-force
smic180-io-config-force:

$(SMIC180_IO_CONFIG_STAMP): smic180-io-config-force
	mkdir -p $(dir $@)
	@{ \
		printf '%s\\n' 'USE_SMIC180_IO=$(USE_SMIC180_IO)'; \
		printf '%s\\n' 'SMIC180_IO_ROOT=$(SMIC180_IO_ROOT)'; \
		printf '%s\\n' 'SMIC180_IO_SIM_SOURCES=$(SMIC180_IO_SIM_SOURCES)'; \
		printf '%s\\n' 'SMIC180_IO_SIM_PREPROC_DEFINES=$(SMIC180_IO_SIM_PREPROC_DEFINES)'; \
	} > $@.tmp; \
	if ! cmp -s $@.tmp $@; then mv $@.tmp $@; else rm -f $@.tmp; fi

.PHONY: smic180-std-config-force
smic180-std-config-force:

$(SMIC180_STD_CONFIG_STAMP): smic180-std-config-force
	mkdir -p $(dir $@)
	@{ \
		printf '%s\\n' 'USE_SMIC180_STD=$(USE_SMIC180_STD)'; \
		printf '%s\\n' 'SMIC180_STD_ROOT=$(SMIC180_STD_ROOT)'; \
		printf '%s\\n' 'SMIC180_STD_SIM_PREPROC_DEFINES=$(SMIC180_STD_SIM_PREPROC_DEFINES)'; \
	} > $@.tmp; \
	if ! cmp -s $@.tmp $@; then mv $@.tmp $@; else rm -f $@.tmp; fi

ifeq ($(USE_TSMC28_SRAM),1)
ifeq ($(USE_SMIC180_SRAM),1)
$(error Set only one of USE_TSMC28_SRAM or USE_SMIC180_SRAM)
endif
endif

ifeq ($(USE_TSMC28_SRAM),1)
TOP_MACROCOMPILER_MODE := --library $(TSMC28_SRAM_MDF) --mode strict
EXT_FILELISTS += $(TSMC28_SRAM_SIM_FILELIST)
EXTRA_SIM_PREPROC_DEFINES += $(TSMC28_SRAM_SIM_PREPROC_DEFINES)
endif

$(TSMC28_SRAM_SIM_FILELIST): $(TSMC28_SRAM_SIM_SOURCES) $(TSMC28_SRAM_CONFIG_STAMP)
	mkdir -p $(dir $@)
	sed 's|^|$(TSMC28_SRAM_ROOT)/|' $< > $@

ifeq ($(USE_SMIC180_SRAM),1)
TOP_MACROCOMPILER_MODE := --library $(SMIC180_SRAM_MDF) --mode strict
EXT_FILELISTS += $(SMIC180_SRAM_SIM_FILELIST)
EXTRA_SIM_FLAGS += $(SMIC180_SRAM_SIM_FLAGS)
endif

$(SMIC180_SRAM_SIM_FILELIST): $(SMIC180_SRAM_SIM_SOURCES) $(SMIC180_SRAM_CONFIG_STAMP)
	mkdir -p $(dir $@)
	sed 's|^|$(SMIC180_SRAM_ROOT)/|' $< > $@

ifneq ($(findstring Buckyball,$(CONFIG)),)
EXTRA_SIM_SOURCES += $(base_dir)/generator/chipyard/src/main/resources/csrc/buckyball_dpi.cc
endif
ifeq ($(USE_SMIC180_IO),1)
EXT_FILELISTS += $(SMIC180_IO_SIM_FILELIST)
EXTRA_SIM_PREPROC_DEFINES += $(SMIC180_IO_SIM_PREPROC_DEFINES)
SIM_CONFIG_STAMPS += $(SMIC180_IO_CONFIG_STAMP)
endif

$(SMIC180_IO_SIM_FILELIST): $(SMIC180_IO_SIM_SOURCES) $(SMIC180_IO_CONFIG_STAMP)
	mkdir -p $(dir $@)
	sed 's|^|$(SMIC180_IO_ROOT)/|' $< > $@

ifeq ($(USE_SMIC180_STD),1)
EXT_FILELISTS += $(SMIC180_STD_SIM_FILELIST)
EXTRA_SIM_PREPROC_DEFINES += $(SMIC180_STD_SIM_PREPROC_DEFINES)
endif

$(SMIC180_STD_SIM_FILELIST): $(SMIC180_STD_CONFIG_STAMP)
	mkdir -p $(dir $@)
	printf '%s\n' '$(SMIC180_STD_ROOT)/verilog/scc018ug_uhd_rvt.v' > $@
