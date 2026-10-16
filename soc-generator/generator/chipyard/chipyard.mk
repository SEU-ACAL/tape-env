# Set one of USE_TSMC28_SRAM or USE_SMIC180_SRAM to compile top-level
# sequential memories with the corresponding hard SRAM macros.
USE_TSMC28_SRAM ?= 0
USE_SMIC180_SRAM ?= 0
# Tapeout configurations always use the physical SMIC180 BootROM and Debug ROM macros.
# The default for unrelated configurations remains the ordinary TLROM.
USE_SMIC180_ROM ?= 0
USE_SMIC180_IO ?= 0
USE_SMIC180_STD ?= 0

# Tapeout configurations are the supported physical SMIC180 configurations.
SMIC180_TAPEOUT_CONFIGS ?= TapeoutConfig TapeoutRocketConfig
ifneq ($(filter $(CONFIG),$(SMIC180_TAPEOUT_CONFIGS)),)
override USE_SMIC180_IO := 1
override USE_SMIC180_STD := 1
override USE_SMIC180_SRAM := 1
override USE_SMIC180_ROM := 1
endif

TSMC28_FDIP_CONFIGS := FDIPMegaBoomV3Config FDIPMegaBoomV3PerfConfig FDIPMegaBoomV3CosimConfig FDIPMegaBoomV3CosimPerfConfig FDIPMegaBoomV3CosimPerfDBConfig
TSMC28_SRAM_PROFILE ?= $(if $(filter $(CONFIG),$(TSMC28_FDIP_CONFIGS)),fdip,legacy)
ifeq ($(TSMC28_SRAM_PROFILE),fdip)
TSMC28_SRAM_ROOT ?= /data2/TSMC28/Memory/SRAM/fdip-20261014
TSMC28_SRAM_MDF ?= $(base_dir)/generator/chipyard/vlsi/fdip_tsmc28_sram_library.mdf.json
TSMC28_SRAM_SIM_SOURCES ?= $(base_dir)/generator/chipyard/vlsi/fdip_tsmc28_sram_sim.sources
else
TSMC28_SRAM_ROOT ?= /data2/TSMC28/Memory/SRAM
TSMC28_SRAM_MDF ?= $(base_dir)/generator/chipyard/vlsi/tsmc28_sram_library.mdf.json
TSMC28_SRAM_SIM_SOURCES ?= $(base_dir)/generator/chipyard/vlsi/tsmc28_sram_sim.sources
endif
TSMC28_SRAM_SIM_FILELIST ?= $(build_dir)/tsmc28_sram_sim.f
TSMC28_SRAM_SIM_PREPROC_DEFINES ?= +define+TSMC_CM_UNIT_DELAY +define+UNIT_DELAY +define+no_warning
TSMC28_SRAM_CONFIG_STAMP ?= $(build_dir)/.tsmc28-sram-config.stamp

SMIC180_SRAM_ROOT ?= /data2/smic180/SRAM/S018SP_v0p1pc_CDK/SMIC180_S018SP_v0p1c_20260722
SMIC180_SRAM_MDF ?= $(base_dir)/generator/chipyard/vlsi/smic180_sram_library.mdf.json
SMIC180_SRAM_SIM_SOURCES ?= $(base_dir)/generator/chipyard/vlsi/smic180_sram_sim.sources
SMIC180_SRAM_SIM_FILELIST ?= $(build_dir)/smic180_sram_sim.f
SMIC180_SRAM_SIM_FLAGS ?= +notimingcheck
SMIC180_SRAM_CONFIG_STAMP ?= $(build_dir)/.smic180-sram-config.stamp

# Tapeout configurations use SMIC S018VM BootROM and Debug ROM macros. The
# effective value is exported for the Chisel config; checking CONFIG here
# prevents unrelated P2E configs from enabling it.
SMIC180_ROM_ENABLED := $(if $(and $(filter $(CONFIG),$(SMIC180_TAPEOUT_CONFIGS)), $(filter 1 yes true,$(USE_SMIC180_ROM))),1,0)
export SMIC180_ROM_ENABLED
# ROM macros are pre-generated physical IP. This flow only consumes the fixed
# Verilog models and never invokes a ROM compiler.
SMIC180_ROM_CACHE_DIR ?= /data2/smic180/rom-ip
SMIC180_ROM_OUTPUT_DIR ?= $(SMIC180_ROM_CACHE_DIR)/bootrom
SMIC180_ROM_MACRO_NAME ?= S018VM_X64Y16D64_PM
SMIC180_ROM_MACRO_V ?= $(SMIC180_ROM_OUTPUT_DIR)/$(SMIC180_ROM_MACRO_NAME).v
SMIC180_DEBUG_ROM_OUTPUT_DIR ?= $(SMIC180_ROM_CACHE_DIR)/debugrom
SMIC180_DEBUG_ROM_MACRO_NAME ?= S018VM_X8Y16D64_PM
SMIC180_DEBUG_ROM_MACRO_V ?= $(SMIC180_DEBUG_ROM_OUTPUT_DIR)/$(SMIC180_DEBUG_ROM_MACRO_NAME).v
SMIC180_ROM_SIM_FILELIST ?= $(build_dir)/smic180_bootrom_sim.f
SMIC180_ROM_CONFIG_STAMP ?= $(build_dir)/.smic180-rom-config.stamp

TOP_MACRO_STAMP_DEPS += $(TSMC28_SRAM_CONFIG_STAMP) $(SMIC180_SRAM_CONFIG_STAMP)
SIM_CONFIG_STAMPS += $(TSMC28_SRAM_CONFIG_STAMP) $(SMIC180_SRAM_CONFIG_STAMP)
SIM_CONFIG_STAMPS += $(SMIC180_ROM_CONFIG_STAMP)

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
		printf '%s\\n' 'TSMC28_SRAM_PROFILE=$(TSMC28_SRAM_PROFILE)'; \
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
ifeq ($(filter $(TSMC28_SRAM_PROFILE),fdip legacy),)
$(error Unsupported TSMC28_SRAM_PROFILE '$(TSMC28_SRAM_PROFILE)'; use fdip or legacy)
endif
TOP_MACROCOMPILER_MODE := --library $(TSMC28_SRAM_MDF) --mode strict
TOP_MACRO_STAMP_DEPS += $(TSMC28_SRAM_MDF)
EXT_FILELISTS += $(TSMC28_SRAM_SIM_FILELIST)
EXTRA_SIM_PREPROC_DEFINES += $(TSMC28_SRAM_SIM_PREPROC_DEFINES)
ifeq ($(TSMC28_SRAM_PROFILE),fdip)
# UHDDPSRAM has one physical CLK. Refuse mappings whose logical ports use
# different clocks, instead of silently discarding the reader's clock.
FDIP_TSMC28_CLOCK_STAMP := $(build_dir)/.fdip-tsmc28-clocks.stamp
TOP_MACRO_STAMP_DEPS += $(FDIP_TSMC28_CLOCK_STAMP)
$(FDIP_TSMC28_CLOCK_STAMP): $(ALL_MODS_FILELIST) $(MFC_TOP_SMEMS_JSON) $(base_dir)/scripts/check-fdip-tsmc28-clocks.py
	python3 $(base_dir)/scripts/check-fdip-tsmc28-clocks.py \
		--metadata $(MFC_TOP_SMEMS_JSON) --hierarchy $(MFC_TOP_HRCHY_JSON) \
		--rtl-dir $(GEN_COLLATERAL_DIR) --report $(build_dir)/fdip-tsmc28-clocks.json
	touch $@
endif
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

.PHONY: smic180-rom-config-force
smic180-rom-config-force:

$(SMIC180_ROM_CONFIG_STAMP): smic180-rom-config-force
	mkdir -p $(dir $@)
	@{ \
		printf '%s\n' 'USE_SMIC180_ROM=$(USE_SMIC180_ROM)'; \
		printf '%s\n' 'SMIC180_ROM_ENABLED=$(SMIC180_ROM_ENABLED)'; \
		printf '%s\n' 'SMIC180_ROM_CACHE_DIR=$(SMIC180_ROM_CACHE_DIR)'; \
		printf '%s\n' 'SMIC180_ROM_OUTPUT_DIR=$(SMIC180_ROM_OUTPUT_DIR)'; \
		printf '%s\n' 'SMIC180_DEBUG_ROM_OUTPUT_DIR=$(SMIC180_DEBUG_ROM_OUTPUT_DIR)'; \
		printf '%s\n' 'SMIC180_ROM_MACRO_NAME=$(SMIC180_ROM_MACRO_NAME)'; \
		printf '%s\n' 'SMIC180_DEBUG_ROM_MACRO_NAME=$(SMIC180_DEBUG_ROM_MACRO_NAME)'; \
	} > $@.tmp; \
	if ! cmp -s $@.tmp $@; then mv $@.tmp $@; else rm -f $@.tmp; fi

ifeq ($(SMIC180_ROM_ENABLED),1)
EXT_FILELISTS += $(SMIC180_ROM_SIM_FILELIST)
EXTRA_SIM_FLAGS += +notimingcheck

# Do not synthesize missing macros. The physical ROM IP must be provisioned in
# the configured cache before this target is built.
$(SMIC180_ROM_MACRO_V) $(SMIC180_DEBUG_ROM_MACRO_V): $(SMIC180_ROM_CONFIG_STAMP)
	@test -f "$@" || { echo "Missing fixed SMIC180 ROM macro: $@" >&2; exit 1; }

$(SMIC180_ROM_SIM_FILELIST): $(SMIC180_ROM_MACRO_V) $(SMIC180_DEBUG_ROM_MACRO_V)
	mkdir -p $(dir $@)
	printf '%s\n%s\n' '$(SMIC180_ROM_MACRO_V)' '$(SMIC180_DEBUG_ROM_MACRO_V)' > $@
endif

EXTRA_SIM_SOURCES += $(base_dir)/generator/chipyard/src/main/resources/csrc/buckyball_dpi.cc
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
