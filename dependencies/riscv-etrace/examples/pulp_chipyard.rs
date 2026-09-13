//! Decode a Chipyard FIFO stream produced by the PULP rv_tracer backend.

use core::num::NonZeroU8;
use std::{collections::HashMap, env, fs, path::PathBuf, process::Command};

use riscv_etrace::{
    binary::{self, Adaptable},
    config, instruction,
    packet::{self, payload::Payload, unit::PULP},
    tracer::{self, Tracer},
};

/// Build a PC -> (encoding, disassembly) map from the workload ELF.  The
/// tracer intentionally stores only control-flow information for regular
/// instructions, so the concrete mnemonic is recovered from the original ELF
/// bytes with the target objdump.
fn load_disassembly(path: &PathBuf) -> HashMap<u64, (u64, String)> {
    let output = Command::new("riscv64-unknown-elf-objdump")
        .args(["-d", "-M", "no-aliases"])
        .arg(path)
        .output()
        .expect("could not execute riscv64-unknown-elf-objdump");
    if !output.status.success() {
        eprintln!(
            "objdump failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        return HashMap::new();
    }
    let text = String::from_utf8_lossy(&output.stdout);
    let mut result = HashMap::new();
    for line in text.lines() {
        let Some((address, rest)) = line.split_once(':') else {
            continue;
        };
        let address = address.trim();
        if address.is_empty() || !address.chars().all(|c| c.is_ascii_hexdigit()) {
            continue;
        }
        let Ok(pc) = u64::from_str_radix(address, 16) else {
            continue;
        };
        let mut fields = rest.split_whitespace();
        let Some(encoding_text) = fields.next() else {
            continue;
        };
        // objdump prints little-endian instruction bytes as a contiguous hex
        // word (for example 00128293); reject data/directive lines.
        if encoding_text.len() < 4
            || encoding_text.len() > 16
            || !encoding_text.chars().all(|c| c.is_ascii_hexdigit())
        {
            continue;
        }
        let Ok(encoding) = u64::from_str_radix(encoding_text, 16) else {
            continue;
        };
        let mnemonic = fields.collect::<Vec<_>>().join(" ").replace(',', ", ");
        if !mnemonic.is_empty() {
            result.insert(pc, (encoding, mnemonic));
        }
    }
    result
}

fn main() {
    let mut args = env::args_os().skip(1);
    let first = args
        .next()
        .expect("usage: pulp_chipyard [--time] TRACE ELF");
    let mut has_time = false;
    let mut trace_arg = first;
    loop {
        if trace_arg == "--time" {
            has_time = true;
        } else {
            break;
        }
        trace_arg = args
            .next()
            .expect("usage: pulp_chipyard [--time] TRACE ELF");
    }
    let trace = PathBuf::from(trace_arg);
    let elf_path = PathBuf::from(
        args.next()
            .expect("usage: pulp_chipyard [--time] TRACE ELF"),
    );
    let disassembly = load_disassembly(&elf_path);
    let trace = fs::read(trace).expect("could not read trace");
    let elf_data = fs::read(elf_path).expect("could not read ELF");
    let elf = elf::ElfBytes::<elf::endian::LittleEndian>::minimal_parse(&elf_data)
        .expect("could not parse ELF");
    let binary = binary::elf::Elf::<_, _, instruction::base::Set>::new(elf)
        .expect("could not construct ELF");
    let params = config::Parameters {
        // rv_tracer is built with TE_ARCH64 and serializes its native XLEN
        // fields in F3/SF1 packets.  Keep the host profile aligned with that
        // packet contract instead of silently decoding it as RV32.
        ecause_width_p: NonZeroU8::new(64).unwrap(),
        // Rocket has compressed instructions; PULP emits addresses with the
        // architectural halfword alignment bit removed.
        iaddress_lsb_p: 0,
        iaddress_width_p: NonZeroU8::new(64).unwrap(),
        nocontext_p: true,
        notime_p: !has_time,
        time_width_p: NonZeroU8::new(64).unwrap(),
        privilege_width_p: NonZeroU8::new(2).unwrap(),
        ..Default::default()
    };
    let mut decoder = packet::builder()
        .with_params(&params)
        .for_unit(PULP)
        .with_hart_index_width(0)
        .with_timestamp_width(0)
        .with_trace_type_width(0)
        .with_compression(false)
        .decoder(&trace);
    let mut tracer: Tracer<_> = tracer::builder()
        .with_binary(binary::Multi::from(vec![binary.boxed()]))
        .with_params(&params)
        .build()
        .expect("could not construct tracer");
    let mut packets = 0usize;
    let mut payload_errors = 0usize;
    let mut instructions = 0usize;
    while decoder.bytes_left() > 0 {
        let packet = match decoder.decode_encap_packet() {
            Ok(packet) => packet,
            Err(err) => {
                eprintln!("truncated E-Trace tail after {packets} packets: {err:?}");
                break;
            }
        };
        let Some(packet) = packet.into_normal() else {
            continue;
        };
        let payload = match packet.decode_payload() {
            Ok(payload) => payload,
            Err(err) => {
                eprintln!("undecodable E-Trace payload after {packets} packets: {err:?}");
                break;
            }
        };
        // This is the direct E-Trace packet decode.  It intentionally
        // precedes tracer processing, which uses the ELF to infer all
        // sequential instructions between encoded control-flow events.
        eprintln!("PULP_ETRACE_RAW packet={packets} {payload:?}");
        let payload = if let Payload::InstructionTrace(
            riscv_etrace::packet::payload::InstructionTrace::Synchronization(
                riscv_etrace::packet::sync::Synchronization::Start(start),
            ),
        ) = payload
        {
            Payload::InstructionTrace(
                riscv_etrace::packet::payload::InstructionTrace::Synchronization(
                    riscv_etrace::packet::sync::Synchronization::Start(start),
                ),
            )
        } else {
            payload
        };
        if let Payload::InstructionTrace(trace) = payload {
            if let riscv_etrace::packet::payload::InstructionTrace::Synchronization(sync) = trace {
                eprintln!("PULP_ETRACE_SYNC packet={packets} {sync:?}");
            }
            // The capture begins while JTAG Debug ROM is executing. Those
            // addresses are not part of the supplied workload ELF; retain the
            // decoder state and recover at the next synchronization packet.
            let mut packet_instructions = 0usize;
            if let Err(err) = tracer.process_payload(&payload) {
                payload_errors += 1;
                if payload_errors <= 8 {
                    eprintln!("  skipped payload {packets}: {err:?}");
                }
            } else {
                tracer.by_ref().for_each(|item| match item {
                    Ok(item) => {
                        let pc = item.pc();
                        if let Some((encoding, mnemonic)) = disassembly.get(&pc) {
                            let width = if *encoding <= 0xffff { 4 } else { 8 };
                            println!("TRACE_INSTRUCTION pc=0x{pc:016x} encoding=0x{encoding:0width$x} {mnemonic}");
                        } else {
                            println!("TRACE_INSTRUCTION pc=0x{pc:016x} encoding=<unavailable> <unavailable>");
                        }
                        instructions += 1;
                        packet_instructions += 1;
                    }
                    Err(err) => {
                        payload_errors += 1;
                        if payload_errors <= 8 {
                            eprintln!("  skipped instruction packet={packets}: {err:?}");
                        }
                    }
                });
            }
            if packet_instructions != 0 {
                eprintln!(
                    "PULP_ETRACE_PACKET_INSTRUCTIONS packet={packets} count={packet_instructions}"
                );
            }
        }
        packets += 1;
    }
    eprintln!(
        "PULP_ETRACE_RECONSTRUCT packets={packets} instructions={instructions} skipped={payload_errors}"
    );
    if instructions == 0 {
        std::process::exit(2);
    }
}
