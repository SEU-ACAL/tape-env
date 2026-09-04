{
  description = "Chipyard SoC generator development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-gcc11.url = "github:NixOS/nixpkgs/nixos-23.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixpkgs-gcc11, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        gcc11Pkgs = import nixpkgs-gcc11 { inherit system; };
        gcc11Stdenv = gcc11Pkgs.overrideCC gcc11Pkgs.stdenv gcc11Pkgs.gcc11;
        # Verilator's C++ frontend is substantially faster with Clang for the
        # large BOOM-generated translation units. Build it from the same
        # nixpkgs-gcc11 input as Spike so its glibc ABI remains compatible with
        # Chipyard's prebuilt cosimulation libraries.
        clangVerilator = (gcc11Pkgs.verilator.override {
          stdenv = gcc11Pkgs.clangStdenv;
        }).overrideAttrs (old: {
          version = "5.048";
          src = gcc11Pkgs.fetchFromGitHub {
            owner = "verilator";
            repo = "verilator";
            rev = "v5.048";
            hash = "sha256-xvqqgbW7L07+NBYzGN2KLhwir58ByShxo4VVPI3pgZk=";
          };
          # The upstream regression driver imports Python's optional `distro`
          # module, which is not part of this package's test closure. Runtime
          # Verilator functionality is validated by Chipyard's simulator test.
          doCheck = false;
        });
        riscvPkgs = pkgs.pkgsCross.riscv64-embedded;
        riscvCc = riscvPkgs.stdenv.cc;
        # Buildroot 2024.05 has Kconfig entries through GCC 14. The wrapper
        # below presents the current GCC 15 toolchain as that supported floor
        # to Buildroot's version probes, without modifying Buildroot sources.
        riscvLinuxPkgs = pkgs.pkgsCross.riscv64;
        riscvLinuxCc = riscvLinuxPkgs.stdenv.cc;
        # Buildroot's external-toolchain probe predates Nix's split sysroot
        # layout: it requires `gcc -print-file-name=libc.a` to name a unified
        # sysroot. Keep the compiler and C library from pkgsCross.riscv64, but
        # present a conventional read-only sysroot for FireMarshal.
        firemarshalRiscvToolchain = pkgs.runCommand "tape-env-firemarshal-riscv64-toolchain" { } ''
          mkdir -p $out/bin $out/sysroot/lib $out/sysroot/usr/include
          ln -s ${riscvLinuxCc}/bin/* $out/bin/
          # Buildroot copies an external sysroot then rewrites absolute
          # symlinks.  Dereference Nix-store links here so its staging copy
          # remains self-contained, including the dynamic loader.
          cp -Lr ${riscvLinuxPkgs.glibc}/lib/. $out/sysroot/lib/
          cp -Lr ${riscvLinuxPkgs.glibc.static}/lib/. $out/sysroot/lib/
          cp -Lr ${riscvLinuxPkgs.glibc.dev}/include/. $out/sysroot/usr/include/
          # Buildroot may reinstall this external sysroot in-place. Preserve
          # Nix's contents but do not propagate store files' read-only modes.
          chmod -R u+w $out/sysroot
          ln -s lib $out/sysroot/lib64
          ln -s ../lib $out/sysroot/usr/lib

          for compiler in gcc g++ c++ cpp cc; do
            rm -f $out/bin/riscv64-unknown-linux-gnu-$compiler
            cat > $out/bin/riscv64-unknown-linux-gnu-$compiler <<'EOF'
          #!${pkgs.runtimeShell}
          toolchain_root="$(cd "$(dirname "$0")/.." && pwd)"
          static_link=0
          has_c_standard=1
          sysroot=
          expect_sysroot_path=0
          filtered_args=()
          if [ "@compiler@" = "gcc" ]; then
            # Buildroot 2024.05 contains packages not yet C23-clean.
            has_c_standard=0
          fi
          for arg in "$@"; do
            if [ "$expect_sysroot_path" -eq 1 ]; then
              sysroot="$arg"
              expect_sysroot_path=0
              continue
            fi
            if [ "$arg" = "-print-file-name=libc.a" ]; then
              printf '%s\n' "$toolchain_root/sysroot/lib/libc.a"
              exit 0
            fi
            if [ "@compiler@" = "gcc" ] \
              && { [ "$arg" = "-dumpversion" ] || [ "$arg" = "-dumpfullversion" ]; }; then
              # Buildroot 2024.05 has version selectors through GCC 14. GCC
              # 15 satisfies its feature floor, but must identify as the
              # highest supported selector during its configuration probes.
              printf '%s\n' '14.3.0'
              exit 0
            fi
            if [ "$arg" = "-static" ]; then
              static_link=1
            fi
            case "$arg" in
              --sysroot)
                expect_sysroot_path=1
                continue
                ;;
              --sysroot=*)
                sysroot="''${arg#--sysroot=}"
                continue
                ;;
              -std=*|--std=*) has_c_standard=1 ;;
            esac
            filtered_args+=("$arg")
          done
          if [ "$expect_sysroot_path" -eq 1 ]; then
            echo "--sysroot requires a path" >&2
            exit 2
          fi
          set -- "''${filtered_args[@]}"
          if [ "@compiler@" = "gcc" ] && [ "$has_c_standard" -eq 0 ]; then
            set -- -std=gnu17 "$@"
          fi
          # Nix's cc-wrapper has absolute glibc linker scripts, which conflict
          # with GNU ld's --sysroot rewriting. Keep its toolchain ABI, but
          # present Buildroot's staging headers and package libraries directly.
          sysroot_flags=()
          if [ -n "$sysroot" ]; then
            sysroot_flags=(
              -isystem "$sysroot/usr/include"
              -isystem "$sysroot/include"
              -L"$sysroot/lib"
              -L"$sysroot/usr/lib"
              -Wl,-rpath-link,"$sysroot/lib"
              -Wl,-rpath-link,"$sysroot/usr/lib"
            )
            if [ "$static_link" -eq 0 ] && [ "@compiler@" != "cpp" ]; then
              sysroot_flags+=(
                -Wl,--dynamic-linker=/lib/ld-linux-riscv64-lp64d.so.1
              )
            fi
          fi
          if [ "$static_link" -eq 1 ]; then
            exec ${riscvLinuxCc}/bin/riscv64-unknown-linux-gnu-@compiler@ \
              -L${riscvLinuxPkgs.glibc.static}/lib "''${sysroot_flags[@]}" "$@"
          fi
          exec ${riscvLinuxCc}/bin/riscv64-unknown-linux-gnu-@compiler@ \
            "''${sysroot_flags[@]}" "$@"
          EOF
            sed -i "s/@compiler@/$compiler/g" $out/bin/riscv64-unknown-linux-gnu-$compiler
            chmod +x $out/bin/riscv64-unknown-linux-gnu-$compiler
          done

          # Nix's cross GCC wrapper exposes binutils under their plain names,
          # whereas autotools detects GCC's companion names.  Buildroot only
          # needs normal archive operations here, so map those aliases to the
          # target GNU binutils shipped with the same toolchain.
          ln -s riscv64-unknown-linux-gnu-ar $out/bin/riscv64-unknown-linux-gnu-gcc-ar
          ln -s riscv64-unknown-linux-gnu-nm $out/bin/riscv64-unknown-linux-gnu-gcc-nm
          ln -s riscv64-unknown-linux-gnu-ranlib $out/bin/riscv64-unknown-linux-gnu-gcc-ranlib
        '';
        riscvTarget = riscvPkgs.stdenv.targetPlatform.config;
        firemarshalPython = pkgs.python3.withPackages (ps: [
          ps.doit
          ps.gitpython
          ps.humanfriendly
          ps.psutil
          ps.pyyaml
        ]);
        # Keep Spike ABI-compatible with the TestChipIP Cospike source. This
        # revision is the one pinned by upstream Chipyard's riscv-isa-sim
        # submodule.
        spike = gcc11Stdenv.mkDerivation {
          pname = "chipyard-spike";
          version = "9c190a07c6838f6392bafa4ad83acea462c7f759";
          src = pkgs.fetchFromGitHub {
            owner = "riscv-software-src";
            repo = "riscv-isa-sim";
            rev = "9c190a07c6838f6392bafa4ad83acea462c7f759";
            hash = "sha256-XmTFBI1tkp0zCw4/SFhlxScYhJsoNHT1GmuhYB8qZho=";
          };
          nativeBuildInputs = [ pkgs.dtc ];
          enableParallelBuilding = true;
          configureFlags = [
            "--with-boost=no"
            "--with-boost-asio=no"
            "--with-boost-regex=no"
          ];
        };
        # Match upstream Chipyard's default prebuilt CIRCT release. Gemmini's
        # Chisel3 annotations are not accepted by newer nixpkgs firtool builds.
        circt = pkgs.stdenvNoCC.mkDerivation {
          pname = "circt";
          version = "1.75.0";
          src = pkgs.fetchurl {
            url = "https://github.com/llvm/circt/releases/download/firtool-1.75.0/circt-full-static-linux-x64.tar.gz";
            hash = "sha256-yl4LCp9PO77KRKPmjo33/z7GQSbXHJHD5ODp7BhMeYQ=";
          };
          sourceRoot = "firtool-1.75.0";
          installPhase = ''
            mkdir -p $out
            cp -a bin lib $out/
          '';
        };
        libglossSrc = pkgs.fetchFromGitHub {
          owner = "ucb-bar";
          repo = "libgloss-htif";
          rev = "39234a16247ab1fa234821b251f1f1870c3de343";
          hash = "sha256-FXuN1xK5133QqoHI4EG7mvhk7K8J6//ar7Y1+IUPER0=";
        };

        rawRiscvUnknownElfTools = pkgs.runCommand "chipyard-raw-riscv64-unknown-elf-tools" { } ''
          mkdir -p $out/bin

          for tool in \
            addr2line ar as c++ c++filt cpp elfedit g++ gcc gcc-ar gcc-nm gcc-ranlib gcov \
            gcov-dump gcov-tool gprof ld ld.bfd nm objcopy objdump ranlib readelf size strings strip
          do
            if command -v ${riscvCc}/bin/riscv64-none-elf-$tool >/dev/null 2>&1; then
              ln -s ${riscvCc}/bin/riscv64-none-elf-$tool $out/bin/riscv64-unknown-elf-$tool
            fi
          done

          ln -s ${spike}/bin/elf2hex $out/bin/elf2hex
          ln -s ${spike}/bin/spike $out/bin/spike
          ln -s ${spike}/bin/spike-dasm $out/bin/spike-dasm
          ln -s ${circt}/bin/firtool $out/bin/firtool
        '';

        libglossHtif = pkgs.stdenv.mkDerivation {
          pname = "chipyard-libgloss-htif";
          version = "local";
          src = libglossSrc;

          nativeBuildInputs = [
            pkgs.autoconf
            pkgs.automake
            pkgs.gnumake
            riscvCc
            rawRiscvUnknownElfTools
          ];

          postPatch = ''
            substituteInPlace misc/crtmain.S \
              --replace-fail "tail exit" "tail _exit"
          '';

          configurePhase = ''
            runHook preConfigure
            mkdir build
            cd build
            ../configure \
              --prefix=$out/riscv64-unknown-elf \
              --libdir=$out/riscv64-unknown-elf/lib \
              --host=riscv64-unknown-elf \
              CC=riscv64-unknown-elf-gcc \
              AR=riscv64-unknown-elf-ar \
              SIZE=riscv64-unknown-elf-size
            runHook postConfigure
          '';

          buildPhase = ''
            runHook preBuild
            make
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/riscv64-unknown-elf/lib
            install -m 0644 libgloss_htif.a $out/riscv64-unknown-elf/lib/
            install -m 0644 ../util/htif.ld $out/riscv64-unknown-elf/lib/
            install -m 0644 ../util/htif.specs $out/riscv64-unknown-elf/lib/
            install -m 0644 ../util/htif_nano.specs $out/riscv64-unknown-elf/lib/
            install -m 0644 ../util/htif_wrap.specs $out/riscv64-unknown-elf/lib/
            install -m 0644 ../util/htif_argv.specs $out/riscv64-unknown-elf/lib/
            runHook postInstall
          '';
        };

        chipyardNewlibNano = (riscvPkgs.newlib.override {
          nanoizeNewlib = true;
        }).overrideAttrs (_old: {
          CFLAGS_FOR_TARGET = "-Os -mcmodel=medany -march=rv64imafd -mabi=lp64d";
        });

        riscvUnknownElfTools = pkgs.runCommand "chipyard-riscv64-unknown-elf-tools" { } ''
          mkdir -p $out/bin $out/include/riscv-pk
          libdir=${libglossHtif}/riscv64-unknown-elf/lib
          nano_libdir=${chipyardNewlibNano}/${riscvTarget}/lib
          nano_incdir=${chipyardNewlibNano}/${riscvTarget}/include
          wrapper_incdir=$out/include

          ln -s ${libglossSrc}/include/encoding.h $out/include/riscv-pk/encoding.h

          make_cc_wrapper() {
            local tool=$1
            local real_tool=${riscvCc}/bin/riscv64-none-elf-$tool
            local wrapper=$out/bin/riscv64-unknown-elf-$tool
            cat > $wrapper <<EOF
#!${pkgs.runtimeShell}
set -e
args=()
for arg in "\$@"; do
  case "\$arg" in
    -specs=htif.specs) args+=("-specs=$libdir/htif.specs") ;;
    -specs=htif_nano.specs) args+=("-specs=$libdir/htif_nano.specs") ;;
    -specs=htif_wrap.specs) args+=("-specs=$libdir/htif_wrap.specs") ;;
    -specs=htif_argv.specs) args+=("-specs=$libdir/htif_argv.specs") ;;
    *) args+=("\$arg") ;;
  esac
done
exec $real_tool -B$libdir/ -B$nano_libdir/ -L$libdir -L$nano_libdir -isystem $nano_incdir -isystem $wrapper_incdir "\''${args[@]}"
EOF
            chmod +x $wrapper
          }

          make_cc_wrapper gcc
          make_cc_wrapper g++
          make_cc_wrapper c++

          for tool in \
            addr2line ar as c++filt cpp elfedit gcc-ar gcc-nm gcc-ranlib gcov \
            gcov-dump gcov-tool gprof ld ld.bfd nm objcopy objdump ranlib readelf size strings strip
          do
            if command -v ${riscvCc}/bin/riscv64-none-elf-$tool >/dev/null 2>&1; then
              ln -s ${riscvCc}/bin/riscv64-none-elf-$tool $out/bin/riscv64-unknown-elf-$tool
            fi
          done

          ln -s ${spike}/bin/elf2hex $out/bin/elf2hex
          ln -s ${spike}/bin/spike $out/bin/spike
          ln -s ${spike}/bin/spike-dasm $out/bin/spike-dasm
          ln -s ${circt}/bin/firtool $out/bin/firtool
        '';

        chipyardRiscvTools = pkgs.runCommand "chipyard-riscv-tools" { } ''
          mkdir -p $out/bin $out/include/riscv-pk $out/lib $out/riscv64-unknown-elf

          ln -s ${riscvUnknownElfTools}/bin/* $out/bin/
          ln -s ${riscvUnknownElfTools}/include/riscv-pk/encoding.h $out/include/riscv-pk/encoding.h
          ln -s ${spike}/include/* $out/include/
          ln -s ${spike}/lib/* $out/lib/

          ln -s ${libglossHtif}/riscv64-unknown-elf/lib $out/riscv64-unknown-elf/lib
        '';

        jtagGdb = gcc11Pkgs.gdb;

        sbt = pkgs.sbt.override { jre = pkgs.jdk17_headless; };

        riscvGdb = pkgs.writeShellScriptBin "riscv64-unknown-elf-gdb" ''
          exec ${jtagGdb}/bin/gdb "$@"
        '';

        mkDevShell = extraPackages: pkgs.mkShellNoCC {
          RISCV = "${chipyardRiscvTools}";
          # FireMarshal's Buildroot configuration requires a Linux-targeted
          # compiler under $RISCV, while Chipyard's existing $RISCV is the
          # bare-metal toolchain used by simulators and bare-metal workloads.
          FIREMARSHAL_RISCV = "${firemarshalRiscvToolchain}";
          FIRTOOL_BIN = "${circt}/bin/firtool";
          JAVA_HOME = "${pkgs.jdk17_headless}";
          VCS_HOME = "/data0/tools/Synopsys/vcs/vcs/W-2024.09-SP1";
          VERDI_HOME = "/data0/tools/Synopsys/verdi/verdi/W-2024.09-SP1";
          LM_LICENSE_FILE = "26000@devjz-ubt20-s01";
          SNPSLMD_LICENSE_FILE = "26000@devjz-ubt20-s01";

          shellHook = ''
            export CY_DIR="$PWD"
            export PATH="$CY_DIR/bin:$VERDI_HOME/bin:$VCS_HOME/bin:$RISCV/bin:$FIREMARSHAL_RISCV/bin:$PATH"
            # A trailing colon means "search the current directory" to the
            # dynamic loader.  Buildroot rejects that unsafe environment.
            if [[ -n "''${LD_LIBRARY_PATH:-}" ]]; then
              export LD_LIBRARY_PATH="${pkgs.zlib}/lib:''${LD_LIBRARY_PATH}"
            else
              export LD_LIBRARY_PATH="${pkgs.zlib}/lib"
            fi
            # VCS's Ubuntu mode exports CPATH=/usr/include/x86_64-linux-gnu
            # to its generated C-source build.  That mixes host glibc bits
            # headers with the Nix GCC wrapper's glibc headers.  On x86_64
            # full64, the generic linux mode still selects VCS's linux64
            # binaries while avoiding that Ubuntu-specific CPATH injection.
            export VCS_ARCH_OVERRIDE=linux
            export ZEPHYR_RISCV="${rawRiscvUnknownElfTools}"
            export FIREMARSHAL_NIX_PATCHELF="${pkgs.patchelf}/bin/patchelf"
            export FIREMARSHAL_NIX_READELF="${pkgs.binutils}/bin/readelf"
            # Buildroot's host-mkpasswd links with -lcrypt directly. Keep that
            # lookup in the Nix closure instead of falling through to /usr/lib.
            export LIBRARY_PATH="${pkgs.libxcrypt}/lib''${LIBRARY_PATH:+:$LIBRARY_PATH}"
            export COURSIER_CACHE="$PWD/.coursier-cache"
            export SBT_OPTS="-Dsbt.global.base=$PWD/.sbt -Dsbt.boot.directory=$PWD/.sbt/boot -Dsbt.ivy.home=$PWD/.ivy2 ''${SBT_OPTS:-}"
            unset NIX_LDFLAGS
            export EXTRA_SIM_CXXFLAGS="-O1 ''${EXTRA_SIM_CXXFLAGS:-}"
            export EXTRA_SIM_LDFLAGS="-no-pie ''${EXTRA_SIM_LDFLAGS:-}"
          '';

          packages = [
            pkgs.autoconf
            pkgs.automake
            pkgs.bash
            pkgs.bison
            pkgs.bc
            pkgs.ccache
            pkgs.cmake
            pkgs.cpio
            pkgs.coreutils
            pkgs.dtc
            pkgs.flex
            gcc11Pkgs.gcc11
            pkgs.git
            pkgs.gnumake
            pkgs.jq
            pkgs.jdk17_headless
            pkgs.libxcrypt
            pkgs.libxslt
            pkgs.ninja
            # numactl 2.0.18 rejects membind on the Linux 5.4 hosts used for simulation.
            # Keep it on the existing nixpkgs-gcc11 input, whose 2.0.16 package supports it.
            gcc11Pkgs.numactl
            pkgs.perl
            pkgs.protobuf
            firemarshalPython
            pkgs.python3Packages.pyelftools
            pkgs.python3Packages.west
            pkgs.ctags
            sbt
            gcc11Pkgs.clang
            clangVerilator
            pkgs.which
            pkgs.zlib
            circt
            riscvCc
          ] ++ extraPackages;
        };

        # Linux workload builds do not need the simulator, Chisel, or
        # bare-metal toolchain closure carried by the default development
        # shell. Keep this shell focused so FireMarshal can be entered and
        # reproduced independently.
        firemarshalShell = pkgs.mkShellNoCC {
          RISCV = "${firemarshalRiscvToolchain}";
          FIREMARSHAL_RISCV = "${firemarshalRiscvToolchain}";

          shellHook = ''
            export CY_DIR="$PWD"
            export PATH="$CY_DIR/bin:$FIREMARSHAL_RISCV/bin:$PATH"
            if [[ -n "''${LD_LIBRARY_PATH:-}" ]]; then
              export LD_LIBRARY_PATH="${pkgs.zlib}/lib:''${LD_LIBRARY_PATH}"
            else
              export LD_LIBRARY_PATH="${pkgs.zlib}/lib"
            fi
            export FIREMARSHAL_NIX_PATCHELF="${pkgs.patchelf}/bin/patchelf"
            export FIREMARSHAL_NIX_READELF="${pkgs.binutils}/bin/readelf"
            export FIREMARSHAL_NIX_FAKEROOT="${pkgs.fakeroot}/bin/fakeroot"
            export FIREMARSHAL_NIX_SH="${pkgs.bash}/bin/sh"
            export FIREMARSHAL_NIX_HOST_CC="${pkgs.stdenv.cc}/bin/gcc"
            export LIBRARY_PATH="${pkgs.libxcrypt}/lib''${LIBRARY_PATH:+:$LIBRARY_PATH}"
            unset NIX_LDFLAGS
          '';

          packages = [
            pkgs.autoconf
            pkgs.automake
            pkgs.bash
            pkgs.bison
            pkgs.bc
            pkgs.cpio
            pkgs.coreutils
            pkgs.dtc
            pkgs.findutils
            pkgs.fakeroot
            pkgs.flex
            pkgs.gawk
            pkgs.git
            pkgs.gnumake
            pkgs.gnutar
            pkgs.gzip
            pkgs.libxcrypt
            pkgs.libxslt
            pkgs.patch
            pkgs.perl
            pkgs.pkg-config
            pkgs.stdenv.cc
            firemarshalPython
            pkgs.python3Packages.pyelftools
            pkgs.wget
            pkgs.which
            pkgs.xz
            pkgs.zlib
          ];
        };

        jtagDebugShell = pkgs.mkShellNoCC {
          packages = [
            gcc11Pkgs.openocd
            jtagGdb
            riscvGdb
          ];
        };

      in {
        packages = {
          inherit chipyardNewlibNano chipyardRiscvTools firemarshalRiscvToolchain libglossHtif rawRiscvUnknownElfTools riscvUnknownElfTools;
        };

        devShells = {
          default = mkDevShell [ ];
          firemarshal = firemarshalShell;
          jtag-debug = jtagDebugShell;
        };
      });
}
