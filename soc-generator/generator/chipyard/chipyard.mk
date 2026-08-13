# Set one of USE_TSMC28_SRAM or USE_SMIC180_SRAM to compile top-level
# sequential memories with the corresponding hard SRAM macros.
USE_TSMC28_SRAM ?= 0
USE_SMIC180_SRAM ?= 0
# Set USE_SMIC180_ROM=1 to replace TapeoutConfig's BootROM with the SMIC
# S018VM macro. The default keeps the ordinary synthesizable TLROM. P2E
# configurations are intentionally excluded below.
USE_SMIC180_ROM ?= 0

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

# TapeoutConfig uses SMIC S018VM BootROM and Debug ROM macros only when
# explicitly enabled. The effective value is exported for the Chisel config;
# checking CONFIG here also prevents P2E's HpecP2E* configs from enabling it.
SMIC180_ROM_ENABLED := $(if $(and $(filter TapeoutConfig,$(CONFIG)), $(filter 1 yes true,$(USE_SMIC180_ROM))),1,0)
export SMIC180_ROM_ENABLED
SMIC180_ROM_CDK_DIR ?= /data2/smic180/S018VM_V0P1PC_CDK
SMIC180_ROM_COMPILER ?= $(base_dir)/generator/chipyard/vlsi/generate_smic180_bootrom.sh
SMIC180_ROM_JAVA ?=
SMIC180_ROM_CODEFILE ?= $(build_dir)/$(long_name).smic180_bootrom.code
SMIC180_DEBUG_ROM_CODEFILE ?= $(build_dir)/$(long_name).smic180_debugrom.code
SMIC180_ROM_OUTPUT_DIR ?= $(build_dir)/smic180-bootrom
SMIC180_ROM_MACRO_NAME ?= S018VM_X512Y16D64_PM
SMIC180_ROM_MACRO_V ?= $(SMIC180_ROM_OUTPUT_DIR)/$(SMIC180_ROM_MACRO_NAME).v
SMIC180_DEBUG_ROM_OUTPUT_DIR ?= $(build_dir)/smic180-debugrom
SMIC180_DEBUG_ROM_MACRO_NAME ?= S018VM_X8Y16D64_PM
SMIC180_DEBUG_ROM_MACRO_V ?= $(SMIC180_DEBUG_ROM_OUTPUT_DIR)/$(SMIC180_DEBUG_ROM_MACRO_NAME).v
SMIC180_ROM_SIM_FILELIST ?= $(build_dir)/smic180_bootrom_sim.f
SMIC180_ROM_CONFIG_STAMP ?= $(build_dir)/.smic180-rom-config.stamp

TOP_MACRO_STAMP_DEPS += $(TSMC28_SRAM_CONFIG_STAMP) $(SMIC180_SRAM_CONFIG_STAMP)
SIM_CONFIG_STAMPS += $(TSMC28_SRAM_CONFIG_STAMP) $(SMIC180_SRAM_CONFIG_STAMP)
EXTRA_GENERATOR_REQS += $(SMIC180_ROM_CONFIG_STAMP)
SIM_CONFIG_STAMPS += $(SMIC180_ROM_CONFIG_STAMP)

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

.PHONY: smic180-rom-config-force
smic180-rom-config-force:

$(SMIC180_ROM_CONFIG_STAMP): smic180-rom-config-force
	mkdir -p $(dir $@)
	@{ \
		printf '%s\n' 'USE_SMIC180_ROM=$(USE_SMIC180_ROM)'; \
		printf '%s\n' 'SMIC180_ROM_ENABLED=$(SMIC180_ROM_ENABLED)'; \
		printf '%s\n' 'SMIC180_ROM_CDK_DIR=$(SMIC180_ROM_CDK_DIR)'; \
		printf '%s\n' 'SMIC180_ROM_JAVA=$(SMIC180_ROM_JAVA)'; \
		printf '%s\n' 'SMIC180_ROM_COMPILER=$(SMIC180_ROM_COMPILER)'; \
		printf '%s\n' 'SMIC180_ROM_MACRO_NAME=$(SMIC180_ROM_MACRO_NAME)'; \
		printf '%s\n' 'SMIC180_DEBUG_ROM_MACRO_NAME=$(SMIC180_DEBUG_ROM_MACRO_NAME)'; \
	} > $@.tmp; \
	if ! cmp -s $@.tmp $@; then mv $@.tmp $@; else rm -f $@.tmp; fi

ifeq ($(SMIC180_ROM_ENABLED),1)
EXT_FILELISTS += $(SMIC180_ROM_SIM_FILELIST)
EXTRA_SIM_FLAGS += +notimingcheck

# The generator writes elaboration artifacts beside FIRRTL, including this
# codefile.  Declare that side effect so a clean Make build orders correctly.
$(SMIC180_ROM_CODEFILE): $(FIRRTL_FILE)
$(SMIC180_DEBUG_ROM_CODEFILE): $(FIRRTL_FILE)

$(SMIC180_ROM_MACRO_V): $(SMIC180_ROM_CODEFILE) $(SMIC180_ROM_COMPILER) $(SMIC180_ROM_CDK_DIR)/S018VM.jar $(SMIC180_ROM_CONFIG_STAMP)
	SMIC180_ROM_JAVA="$(SMIC180_ROM_JAVA)" SMIC180_ROM_MACRO_NAME="$(SMIC180_ROM_MACRO_NAME)" SMIC180_ROM_WORDS=8192 SMIC180_ROM_BITS=64 $(SMIC180_ROM_COMPILER) $(SMIC180_ROM_CDK_DIR) $(SMIC180_ROM_CODEFILE) $(SMIC180_ROM_OUTPUT_DIR)

$(SMIC180_DEBUG_ROM_MACRO_V): $(SMIC180_DEBUG_ROM_CODEFILE) $(SMIC180_ROM_COMPILER) $(SMIC180_ROM_CDK_DIR)/S018VM.jar $(SMIC180_ROM_CONFIG_STAMP)
	SMIC180_ROM_JAVA="$(SMIC180_ROM_JAVA)" SMIC180_ROM_MACRO_NAME="$(SMIC180_DEBUG_ROM_MACRO_NAME)" SMIC180_ROM_WORDS=128 SMIC180_ROM_BITS=64 $(SMIC180_ROM_COMPILER) $(SMIC180_ROM_CDK_DIR) $(SMIC180_DEBUG_ROM_CODEFILE) $(SMIC180_DEBUG_ROM_OUTPUT_DIR)

$(SMIC180_ROM_SIM_FILELIST): $(SMIC180_ROM_MACRO_V) $(SMIC180_DEBUG_ROM_MACRO_V)
	mkdir -p $(dir $@)
	printf '%s\n%s\n' '$(SMIC180_ROM_MACRO_V)' '$(SMIC180_DEBUG_ROM_MACRO_V)' > $@
endif
