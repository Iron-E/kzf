# kzf

`kzf` is an fzf-powered Kubernetes TUI.

<details><summary>Preview</summary>

<img width="1887" height="471" alt="cap" src="https://github.com/user-attachments/assets/2c4de5e8-6b59-4db1-a6d5-6038048945e1" />

TODO: add gif


</details>

## Installation

### Manual

**Requirements:**

- `bash`
- `curl`
- `fzf`
- `getopt` (unixtools)
- `kubectl`
- A `$PAGER`

Clone this repository and copy [src/kzf.sh](./src/kzf.sh) to any location in your `$PATH`.

### Nix Flake

> [!TIP]
>
> You can try `kzf` without changing any Nix configuration:
>
> ```sh
> # run kzf
> nix run github:Iron-E/kzf
>
> # enter a temporary shell with kzf installed
> nix shell github:Iron-E/kzf
> ```

**Requirements:**

- A `$PAGER`

Add `kzf` to your flake inputs:

```nix
{
  # ...
  inputs = {
    # ...

    kzf.url = "github:Iron-E/kzf";

    # ...
  };

  outputs = inputs@{ ... }: {
    # ...
  };
}
```

Then, you can reference `kzf` in `outputs` as `inputs.kzf.packages.<SYSTEM>.default` (e.g. `inputs.kzf.packages."x86_64-linux".default`.

## Usage

> [!NOTE]
>
> `kzf` can integrate with the following tools:
>
> - `kubecolor`
> - `tspin` (tailspin)
> - `viddy`
> - `zellij`

See `kzf -h` for help information, and press F1 while inside `kzf` to see a list of keyboard shortcuts.

## Configuration

There is no built-in configuration mechanism for `kzf`. Instead, one may use e.g. aliases.

## Contributing

The [nix flake](./flake.nix) contains a developer environment.
This environment configures pre-commit hooks and vendors dev dependencies.

Please try to use it when contributing to the project.

## Similar Projects

- [k9s](https://github.com/derailed/k9s)
- [kdash](https://github.com/kdash-rs/kdash)
