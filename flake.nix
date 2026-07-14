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
        gcc11ForVcs = pkgs.runCommand "gcc11-for-vcs" { } ''
          mkdir -p $out/bin
          ln -s ${gcc11Pkgs.gcc11}/bin/gcc $out/bin/gcc
        '';
        riscvPkgs = pkgs.pkgsCross.riscv64-embedded;
        riscvCc = riscvPkgs.stdenv.cc;
        riscvTarget = riscvPkgs.stdenv.targetPlatform.config;
        # Keep Spike ABI-compatible with the TestChipIP Cospike source. This
        # revision is the one pinned by upstream Chipyard's riscv-isa-sim
        # submodule.
        spike = pkgs.stdenv.mkDerivation {
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

      in {
        packages = {
          inherit chipyardNewlibNano chipyardRiscvTools libglossHtif rawRiscvUnknownElfTools riscvUnknownElfTools;
        };

        devShells.default = pkgs.mkShellNoCC {
          RISCV = "${chipyardRiscvTools}";
          FIRTOOL_BIN = "${circt}/bin/firtool";
          JAVA_HOME = "${pkgs.jdk17_headless}";

          shellHook = ''
            export CY_DIR="$PWD"
            export PATH="$RISCV/bin:$PATH"
            export ZEPHYR_RISCV="${rawRiscvUnknownElfTools}"
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
            pkgs.cmake
            pkgs.coreutils
            pkgs.dtc
            pkgs.flex
            gcc11ForVcs
            pkgs.gcc
            pkgs.git
            pkgs.gnumake
            pkgs.jq
            pkgs.jdk17_headless
            pkgs.ninja
            pkgs.numactl
            pkgs.perl
            pkgs.python3
            pkgs.python3Packages.pyelftools
            pkgs.python3Packages.west
            pkgs.ctags
            pkgs.sbt
            pkgs.verilator
            pkgs.which
            circt
            riscvCc
          ];
        };
      });
}
