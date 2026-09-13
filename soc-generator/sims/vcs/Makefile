#########################################################################################
# vcs makefile
#########################################################################################

#########################################################################################
# general path variables
#########################################################################################
base_dir=$(abspath ../..)
sim_dir=$(abspath .)

#########################################################################################
# include shared variables
#########################################################################################
include $(base_dir)/variables.mk

#########################################################################################
# name of simulator (used to generate *.f arguments file)
#########################################################################################
sim_name = vcs

#########################################################################################
# vcs simulator types and rules
#########################################################################################
sim_prefix = simv
sim = $(sim_dir)/$(sim_prefix)-$(MODEL_PACKAGE)-$(CONFIG)
sim_debug = $(sim_dir)/$(sim_prefix)-$(MODEL_PACKAGE)-$(CONFIG)-debug

include $(sim_dir)/vcs.mk

.DEFAULT_GOAL := default

# VCS requires package declarations before the blackbox modules that import
# them.  FIRRTL emits these files as blackbox resources, but its generic
# simulator filelist is sorted alphabetically.  Keep this workaround local to
# the PULP configuration and leave the original trace configuration unchanged.
ifneq (,$(filter RocketPulpTraceConfig TapeoutConfig TapeoutRocketConfig,$(CONFIG)))
# The tracer RTL is packaged as Rocket-Chip black-box resources.  Compile the
# generated copies exactly once, before the alphabetically sorted generic list,
# so te_pkg is defined before modules that import it.
PULP_RV_TRACER_ROOT := $(abspath $(base_dir)/generator/rocket-chip/src/main/resources/vsrc/rv_tracer)
PULP_RV_TRACER_SOURCES := $(wildcard $(PULP_RV_TRACER_ROOT)/*.sv)
PULP_RV_TRACER_FILELIST := $(build_dir)/pulp_rv_tracer.f
EXT_FILELISTS += $(PULP_RV_TRACER_FILELIST)
# VCS consumes EXT_FILELISTS at command execution time, so make must also
# model this file as a prerequisite of the simulator binary.
EXTRA_SIM_REQS += $(PULP_RV_TRACER_FILELIST)
SIM_COMMON_FILES_EXCLUDE := /gen-collateral/(te_pkg|rv_tracer_math_compat|rv_tracer_compat|lzc|te_reg|te_resync_counter|te_branch_map|te_filter|te_priority|te_packet_emitter|rv_tracer|rv_tracer_wrapper)\.sv$$
# This is also defined by common.mk below, but the tracer rules are declared
# before that include and therefore need the value during immediate expansion.
FIRTOOL_STAMP ?= $(build_dir)/.firtool.stamp

# Keep the generated wrapper aligned with its resource source after firtool
# recreates the collateral directory.
$(GEN_COLLATERAL_DIR)/rv_tracer_wrapper.sv: $(PULP_RV_TRACER_SOURCES) $(FIRTOOL_STAMP) | $(GEN_COLLATERAL_DIR)
	# VCS resolves the package used by lzc during textual inclusion.  This
	# applies the required ordering only to the disposable simulation copy.
	mkdir -p $(GEN_COLLATERAL_DIR)
	cp -f $(PULP_RV_TRACER_SOURCES) $(GEN_COLLATERAL_DIR)
	sed '/`include "lzc.sv"/{N;s/`include "lzc.sv"\n`include "rv_tracer_math_compat.sv"/`include "rv_tracer_math_compat.sv"\n`include "lzc.sv"/;}' $(PULP_RV_TRACER_ROOT)/rv_tracer_wrapper.sv > $@

$(PULP_RV_TRACER_FILELIST): $(sim_dir)/Makefile $(FIRTOOL_STAMP) $(GEN_COLLATERAL_DIR)/rv_tracer_wrapper.sv
	@mkdir -p $(dir $@)
	@printf '%s\n' \
		$(GEN_COLLATERAL_DIR)/rv_tracer_wrapper.sv > $@
endif

.PHONY: default debug
default: $(sim)
debug: $(sim_debug)

#########################################################################################
# simulation requirements
#########################################################################################
SIM_FILE_REQS += \
	$(ROCKETCHIP_RSRCS_DIR)/vsrc/TestDriver.v
SIM_COPIED_FILE_REQS := $(addprefix $(GEN_COLLATERAL_DIR)/,$(notdir $(SIM_FILE_REQS)))

$(SIM_COPIED_FILE_REQS): $(SIM_FILE_REQS) | $(GEN_COLLATERAL_DIR)
	cp -f $(SIM_FILE_REQS) $(GEN_COLLATERAL_DIR)

# copy files but ignore *.h files in *.f since vcs has +incdir+$(build_dir)
$(sim_files): $(SIM_COPIED_FILE_REQS) $(ALL_MODS_FILELIST) $(sim_dir)/Makefile | $(GEN_COLLATERAL_DIR)
	rm -f $@
	$(foreach file,\
		$(SIM_FILE_REQS),\
		$(if $(filter %.h,$(file)),\
			,\
			echo "$(addprefix $(GEN_COLLATERAL_DIR)/, $(notdir $(file)))" >> $@;))

#########################################################################################
# import other necessary rules and variables
#########################################################################################
include $(base_dir)/common.mk

# firtool recreates GEN_COLLATERAL_DIR from scratch.  Copy TestDriver only
# after that step so a VCS run cannot retain a stale filelist entry.
$(SIM_COPIED_FILE_REQS): $(FIRTOOL_STAMP)

#########################################################################################
# vcs binary and arguments
#########################################################################################
VCS = vcs -full64

VCS_OPTS = $(VCS_CC_OPTS) $(VCS_NONCC_OPTS) $(SIM_PREPROC_DEFINES) $(VCS_PREPROC_DEFINES)
# VCS uses incremental compilation by default, which can retain a stale simv
# even after FIRRTL regenerates collateral.  Verification runs can request a
# provenance-safe binary without making ordinary developer builds expensive.
ifneq ($(VCS_FORCE_FULL),)
VCS_OPTS += -noIncrComp
endif
ifneq (,$(filter RocketPulpTraceConfig TapeoutConfig TapeoutRocketConfig,$(CONFIG)))
# Upstream rv_tracer has intentional parameterized width casts which VCS
# reports as PCWM-L; preserve the lint diagnostics but do not make them fatal.
VCS_OPTS += -error=noPCWM-L
# The generic SRAM timing models in this simulation configuration report
# asynchronous loadmem activity as timing violations.  This trace bring-up is
# functional RTL validation, so disable timing checks at VCS run time only.
SIM_FLAGS += +notimingcheck
endif

#########################################################################################
# vcs build paths
#########################################################################################
model_dir = $(build_dir)/$(long_name)
model_dir_debug = $(build_dir)/$(long_name).debug

#########################################################################################
# vcs simulator rules
#########################################################################################


$(sim): $(sim_common_files) $(dramsim_lib) $(EXTRA_SIM_REQS)
	$(call require_cmd,vcs)
	$(require_riscv)
	rm -rf $(model_dir)
	$(if $(VCS_FORCE_FULL),rm -f $@)
	$(VCS) $(VCS_OPTS) $(EXTRA_SIM_SOURCES) -o $@ -Mdir=$(model_dir)

$(sim_debug): $(sim_common_files) $(dramsim_lib) $(EXTRA_SIM_REQS)
	$(call require_cmd,vcs)
	$(require_riscv)
	rm -rf $(model_dir_debug)
	$(VCS) $(VCS_OPTS) $(EXTRA_SIM_SOURCES) -o $@ -Mdir=$(model_dir_debug)  \
	+define+DEBUG -debug_access+all -kdb -lca

#########################################################################################
# create vcs vpd/fsdb rules
#########################################################################################
.PRECIOUS: $(output_dir)/%.vpd %.vpd
$(output_dir)/%.vpd: $(output_dir)/% $(sim_debug)
	(set -o pipefail && $(sim_debug) $(PERMISSIVE_ON) $(SIM_FLAGS) $(EXTRA_SIM_FLAGS) $(SEED_FLAG) $(VERBOSE_FLAGS) +vcdplusfile=$@ $(PERMISSIVE_OFF) $< </dev/null 2> >(spike-dasm > $<.out) | tee $<.log)

.PRECIOUS: $(output_dir)/%.fsdb %.fsdb
$(output_dir)/%.fsdb: $(output_dir)/% $(sim_debug)
	(set -o pipefail && $(sim_debug) $(PERMISSIVE_ON) $(SIM_FLAGS) $(EXTRA_SIM_FLAGS) $(SEED_FLAG) $(VERBOSE_FLAGS) +fsdbfile=$@ $(PERMISSIVE_OFF) $< </dev/null 2> >(spike-dasm > $<.out) | tee $<.log)


#########################################################################################
# general cleanup rules
#########################################################################################
.PHONY: clean clean-sim clean-sim-debug
clean:
	rm -rf $(CLASSPATH_CACHE) $(gen_dir) $(sim_prefix)-* ucli.key

clean-sim:
	rm -rf $(model_dir) $(build_dir)/vc_hdrs.h $(sim) $(sim).daidir ucli.key

clean-sim-debug:
	rm -rf $(model_dir_debug) $(build_dir)/vc_hdrs.h $(sim_debug) $(sim_debug).daidir ucli.key
