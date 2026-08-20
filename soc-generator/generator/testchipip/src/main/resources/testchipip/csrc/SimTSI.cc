#include <vpi_user.h>
#include <svdpi.h>
#include <map>
#include <string>
#include "testchip_tsi.h"

std::map<int, testchip_tsi_t*> tsis;

// Copy simulator arguments while leaving VPI's argv untouched.  Verilog
// endpoints use the original plusargs (for example +xsperf) at simulation
// shutdown, so mutating vpi_get_vlog_info().argv breaks those checks.
void filter_simulator_opts(int argc, char **argv,
                           std::vector<std::string>& storage,
                           std::vector<char*>& filtered){
    storage.reserve(argc);
    filtered.reserve(argc);
    for (int idx = 0; idx < argc; ++idx) {
        std::string str(argv[idx]);
        bool is_vcs_simv_opt = str.length() > 1 && str[0] == '-' && str[1] != '-' && str.find('=') != std::string::npos;
        bool is_testdriver_opt = str == "+cycle-count" || str == "+xsperf" || str.rfind("+max-cycles=", 0) == 0;
        if (!is_vcs_simv_opt && !is_testdriver_opt) {
            storage.push_back(str);
        }
    }
    for (auto& arg : storage)
        filtered.push_back(arg.data());
}

extern "C" int tsi_tick(
                        int chip_id,
                        unsigned char out_valid,
                        unsigned char *out_ready,
                        int out_bits,

                        unsigned char *in_valid,
                        unsigned char in_ready,
                        int *in_bits)
{
    bool out_fire = *out_ready && out_valid;
    bool in_fire = *in_valid && in_ready;
    bool in_free = !(*in_valid);

    auto it = tsis.find(chip_id);

    if (it == tsis.end()) {
        s_vpi_vlog_info info;
        if (!vpi_get_vlog_info(&info))
          abort();

        // Prevent simulator controls from being interpreted as HTIF arguments
        // without changing the argv used by Verilog plusarg handlers.
        std::vector<std::string> filtered_storage;
        std::vector<char*> filtered_argv;
        filter_simulator_opts(info.argc, info.argv, filtered_storage, filtered_argv);

        // TODO: We should somehow inspect whether or not our backing memory supports loadmem, instead of unconditionally setting it to true
        tsis[chip_id] = new testchip_tsi_t(static_cast<int>(filtered_argv.size()), filtered_argv.data(), true);
    }

    testchip_tsi_t* tsi = tsis[chip_id];
    tsi->tick(out_valid, out_bits, in_ready);
    tsi->switch_to_host();

    *in_valid = tsi->in_valid();
    *in_bits = tsi->in_bits();
    *out_ready = tsi->out_ready();

    return tsi->done() ? (tsi->exit_code() << 1 | 1) : 0;
}
