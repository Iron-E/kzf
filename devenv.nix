{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

{
  # https://devenv.sh/packages/
  packages = with pkgs; [
    fzf
    kubectl
    tailspin
  ];

  # https://devenv.sh/languages/
  languages.go.enable = true;

  # https://devenv.sh/git-hooks/
  git-hooks.hooks = {
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

  # https://devenv.sh/tasks/
  tasks = {
    "kzf:build".exec = "go build cmd/kzf";
    "kzf:run".exec = "go run cmd/kzf";
    "kzf:mod:tidy" = {
      exec = "go mod tidy";
      before = [
        "kzf:build"
        "kzf:run"
      ];
    };
  };

  # See full reference at https://devenv.sh/reference/options/
}
