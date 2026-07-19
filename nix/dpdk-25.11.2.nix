# SPDX-License-Identifier: Apache-2.0
{ lib, stdenv, fetchurl, meson, ninja, pkg-config, python3, numactl, libbsd, libelf, zlib }:

stdenv.mkDerivation (finalAttrs: {
  pname = "dpdk";
  version = "25.11.2";

  src = fetchurl {
    url = "https://fast.dpdk.org/rel/dpdk-${finalAttrs.version}.tar.xz";
    hash = "sha256-QYv+MhJkDulaHLEK9u02DK0jh2hv4nIfijqc0C1e9PI=";
  };

  nativeBuildInputs = [ meson ninja pkg-config (python3.withPackages (ps: [ ps.pyelftools ])) ];
  buildInputs = [ numactl libbsd libelf zlib ];

  mesonFlags = [
    "-Dplatform=generic"
    "-Dcpu_instruction_set=generic"
    "-Ddeveloper_mode=disabled"
    "-Dtests=false"
    "-Dexamples="
    "-Denable_drivers=net/ring"
    "-Dmax_lcores=64"
    "-Dmax_numa_nodes=8"
  ];

  postInstall = ''
    mkdir -p "$out/share/saint-shield/integrity"
    cat > "$out/share/saint-shield/integrity/dpdk-source.txt" <<'EOF'
    version=25.11.2
    url=https://fast.dpdk.org/rel/dpdk-25.11.2.tar.xz
    sri=sha256-QYv+MhJkDulaHLEK9u02DK0jh2hv4nIfijqc0C1e9PI=
    EOF
  '';

  meta = {
    description = "DPDK 25.11.2 LTS, narrowed to the virtual ring PMD for Saint Shield CI";
    homepage = "https://www.dpdk.org/";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
})
