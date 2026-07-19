{
  description = "Saint Shield reproducible development and verification environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/61b7c44c4073f0b827768aff0049561b5110ea5a";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          dpdk = pkgs.callPackage ./nix/dpdk-25.11.2.nix { };
        in {
          inherit dpdk;
          default = dpdk;
        });

      checks = forAllSystems (system: {
        dpdk-25-11-2 = self.packages.${system}.dpdk;
      });

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          dpdk = self.packages.${system}.dpdk;
          python = pkgs.python3.withPackages (ps: [ ps.jsonschema ps.scapy ]);
          linuxOnly = nixpkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.linuxPackages.perf ];
        in {
          default = pkgs.mkShell {
            strictDeps = true;
            packages = [
              pkgs.zig
              dpdk
              pkgs.aflplusplus
              pkgs.check-jsonschema
              pkgs.clang
              pkgs.llvm
              pkgs.meson
              pkgs.ninja
              pkgs.pkg-config
              pkgs.gcc
              pkgs.gnumake
              pkgs.jq
              pkgs.mkdocs
              pkgs.linkchecker
              pkgs.tlaplus
              python
            ] ++ linuxOnly;

            DPDK_PREFIX = "${dpdk}";
            SAINT_SHIELD_ZIG_VERSION = pkgs.zig.version;
            SAINT_SHIELD_DPDK_VERSION = dpdk.version;
            SAINT_SHIELD_SCAPY_VERSION = pkgs.python3Packages.scapy.version;
            SAINT_SHIELD_AFL_VERSION = pkgs.aflplusplus.version;
            SAINT_SHIELD_TLA_VERSION = pkgs.tlaplus.version;

            shellHook = ''
              if [ "$SAINT_SHIELD_ZIG_VERSION" != "0.16.0" ]; then
                echo "Saint Shield requires Zig 0.16.0 exactly" >&2
                return 1
              fi
              if [ "$SAINT_SHIELD_DPDK_VERSION" != "25.11.2" ]; then
                echo "Saint Shield requires DPDK 25.11.2 exactly" >&2
                return 1
              fi
            '';
          };
        });
    };
}

