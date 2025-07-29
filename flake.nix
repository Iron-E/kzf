{
  description = "kzf";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      pre-commit-hooks,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      name = "kzf";
      version = "0.1.0";

      genSystems = lib.genAttrs [
        "aarch64-darwin"
        "aarch64-linux"
        "i686-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ ];
        };

      mkDeps =
        pkgs: with pkgs; [
          curlMinimal
          fzf
          kubectl
          unixtools.getopt
        ];

      # bash is already installed by nix develop
      mkDevDeps =
        pkgs: with pkgs; [
          bashInteractive
          reuse
        ];
    in
    {
      checks = genSystems (system: {
        pre-commit-check = pre-commit-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            check-added-large-files.enable = true;
            check-json.enable = true;
            detect-aws-credentials.enable = true;
            detect-private-keys.enable = true;
            end-of-file-fixer.enable = true;
            gofmt.enable = true;
            golangci-lint.enable = true;
            hadolint.enable = true;
            nixfmt-rfc-style.enable = true;
            shellcheck.enable = true;
            stylua.enable = true;
            trim-trailing-whitespace.enable = true;
          };
        };
      });

      devShells = genSystems (
        system:
        let
          inherit (self.checks.${system}) pre-commit-check;
          pkgs = mkPkgs system;
        in
        {
          default = pkgs.mkShell {
            inherit name;

            inherit (pre-commit-check) shellHook;
            buildInputs = pre-commit-check.enabledPackages;

            packages = (mkDeps pkgs) ++ (mkDevDeps pkgs);
          };
        }
      );

      packages = genSystems (
        system:
        let
          pkgs = mkPkgs system;

          kzf = pkgs.writeShellApplication {
            inherit name;

            derivationArgs = { inherit version; };
            meta = {
              description = "fzf-powered Kubernetes TUI";
              homepage = "https://github.com/Iron-E/kzf";
              license = with lib.licenses; [ unfree ];
              mainProgram = "kzf";
            };

            runtimeInputs = mkDeps pkgs;

            # handled by the script
            bashOptions = [ ];

            text = lib.pipe ./src/kzf.sh [
              builtins.readFile
              (lib.splitString "\n")
              (lib.drop 1)
              lib.concatLines
            ];
          };
        in
        {
          inherit kzf;
          default = kzf;
        }
      );
    };
}
