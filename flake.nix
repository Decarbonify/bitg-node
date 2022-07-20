{
  inputs = {
    nixpkgs.url = github:nixos/nixpkgs;
    flake-utils = {
      url = github:numtide/flake-utils;
      inputs.nixpkgs.follows = "nixpkgs";
    };
    naersk = {
      url = github:nix-community/naersk;
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , naersk
    }:
    flake-utils.lib.eachDefaultSystem (system:
    let
      lib = nixpkgs.lib;
      pkgs = nixpkgs.legacyPackages.${system};
      rustTools = import ./nix/rust.nix {
        nixpkgs = pkgs;
      };
      getRust =
        { channel ? "nightly"
        , date
        , sha256
        , targets ? [
            "wasm32-unknown-unknown"
            "wasm32-wasi"
            # "wasm32-unknown-emscripten"
          ]
        }: (rustTools.rustChannelOf {
          inherit channel date sha256;
        }).rust.override {
          inherit targets;
          extensions = [ "rust-src" "rust-analysis" ];
        };
      rust2022-03-15 = getRust { date = "2022-03-15"; sha256 = "sha256-C7X95SGY0D7Z17I8J9hg3z9cRnpXP7FjAOkvEdtB9nE="; };
      rust2022-06-30 = getRust { date = "2022-06-30"; sha256 = "sha256-p/GQnKKCVenhxVd4cRK1CYFADkbqmV5paAV/4Ca/Dhs="; };
      rust = rust2022-06-30;
      # Get a naersk with the input rust version
      naerskWithRust = rust: naersk.lib."${system}".override {
        rustc = rust;
        cargo = rust;
      };
      env = with pkgs; {
        LIBCLANG_PATH = "${llvmPackages.libclang.lib}/lib";
        PROTOC = "${protobuf}/bin/protoc";
        ROCKSDB_LIB_DIR = "${rocksdb}/lib";
      };
      # Naersk using the default rust version
      buildRustProject = pkgs.makeOverridable ({ rust, naersk ? naerskWithRust rust, ... } @ args: with pkgs; naersk.buildPackage ({
        buildInputs = [
          clang
          pkg-config
        ] ++ lib.optionals stdenv.isDarwin [
          darwin.apple_sdk.frameworks.Security
        ];
        copyLibs = true;
        copyBins = true;
        targets = [ ];
        remapPathPrefix =
          true; # remove nix store references for a smaller output package
      } // env // args));

      crateName = "bitg-node";
      root = ./.;
      # This is a wrapper around naersk build
      # Remember to add Cargo.lock to git for naersk to work
      project = buildRustProject {
        inherit root rust;
        copySources = [ "bridges" "node" "pallets" "oracles" "parachain" "primitives" "runtime" "rpc" "tools" ];
      };
      # Running tests
      testProject = project.override {
        doCheck = true;
      };
    in
    {
      packages = {
        ${crateName} = project;
        "${crateName}-test" = testProject;
      };

      defaultPackage = self.packages.${system}.${crateName};

      # `nix develop`
      devShell = pkgs.mkShell (env // {
        inputsFrom = builtins.attrValues self.packages.${system};
        nativeBuildInputs = [ rust ];
        buildInputs = with pkgs; [
          rust-analyzer
          clippy
          rustfmt
        ];
      });
    });
}
