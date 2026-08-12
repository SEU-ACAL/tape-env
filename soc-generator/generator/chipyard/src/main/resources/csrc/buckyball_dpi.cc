extern "C" {

void dpi_itrace(unsigned, unsigned, unsigned, unsigned, unsigned, unsigned,
                unsigned, unsigned, unsigned, unsigned, unsigned, unsigned,
                unsigned, unsigned, unsigned) {}

void dpi_mtrace(unsigned, unsigned, unsigned, unsigned, unsigned, unsigned,
                unsigned, unsigned, unsigned, unsigned, unsigned, unsigned,
                unsigned, unsigned, unsigned) {}

void dpi_mtrace_issue(unsigned, unsigned, unsigned, unsigned, unsigned,
                      unsigned) {}

void dpi_pmctrace(unsigned, unsigned, unsigned, unsigned) {}

void dpi_mem_pmctrace(unsigned, unsigned, unsigned, unsigned) {}

void dpi_bdb_set_clk(unsigned long long) {}

void dpi_ctrace(unsigned, unsigned, unsigned, unsigned, unsigned, unsigned,
                unsigned, unsigned) {}

}
