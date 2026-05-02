{
  description = "tiny-gpu HaDes-V: RV32IM GPGPU with INT4/sparsity/OoO for Intel FPGAs";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        # Default dev shell — identical to nix/shell.nix
        devShells.default = import ./shell.nix { inherit pkgs; };

        # Simulation build: produces a compiled Verilog artifact
        packages.simulation = pkgs.stdenv.mkDerivation {
          name    = "tiny-gpu-hadesv-sim";
          src     = ../.;

          buildInputs = with pkgs; [
            iverilog
            sv2v
            python3
            python3Packages.cocotb
          ];

          buildPhase   = "make compile";
          installPhase = ''
            mkdir -p $out
            cp build/gpu.v $out/gpu.v
          '';
        };

        # Development shell with extra analysis tools
        devShells.full = pkgs.mkShell {
          name = "tiny-gpu-hadesv-full";
          inputsFrom = [ self.devShells.${system}.default ];
          buildInputs = with pkgs; [
            yosys       # Open-source synthesis (structural analysis, not timing)
            nextpnr     # Open-source place-and-route (ECP5 / iCE40 only, not Intel)
          ];
          shellHook = ''
            source ${self.devShells.${system}.default}/nix-support/setup-hook 2>/dev/null || true
            echo "  Full shell: adds yosys + nextpnr for open-source synthesis analysis."
          '';
        };
      }
    );
}
