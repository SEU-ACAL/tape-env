# Set USE_TSMC28_SRAM=1 to compile top-level sequential memories with the
# TSMC28 SRAM macros described by this fragment.
USE_TSMC28_SRAM ?= 0

TSMC28_SRAM_ROOT ?= /data2/TSMC28/Memory/SRAM
TSMC28_SRAM_MDF ?= $(base_dir)/generator/chipyard/vlsi/tsmc28_sram_library.mdf.json
TSMC28_SRAM_SIM_SOURCES ?= $(base_dir)/generator/chipyard/vlsi/tsmc28_sram_sim.sources
TSMC28_SRAM_SIM_FILELIST ?= $(build_dir)/tsmc28_sram_sim.f
TSMC28_SRAM_SIM_PREPROC_DEFINES ?= +define+UNIT_DELAY +define+no_warning
TSMC28_SRAM_CONFIG_STAMP ?= $(build_dir)/.tsmc28-sram-config.stamp

TOP_MACRO_STAMP_DEPS += $(TSMC28_SRAM_CONFIG_STAMP)
SIM_CONFIG_STAMPS += $(TSMC28_SRAM_CONFIG_STAMP)

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

ifeq ($(USE_TSMC28_SRAM),1)
TOP_MACROCOMPILER_MODE := --library $(TSMC28_SRAM_MDF) --mode strict
EXT_FILELISTS += $(TSMC28_SRAM_SIM_FILELIST)
EXTRA_SIM_PREPROC_DEFINES += $(TSMC28_SRAM_SIM_PREPROC_DEFINES)
endif

$(TSMC28_SRAM_SIM_FILELIST): $(TSMC28_SRAM_SIM_SOURCES) $(TSMC28_SRAM_CONFIG_STAMP)
	mkdir -p $(dir $@)
	sed 's|^|$(TSMC28_SRAM_ROOT)/|' $< > $@
