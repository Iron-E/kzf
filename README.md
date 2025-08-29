# kzf

`kzf` is an fzf-powered Kubernetes TUI.

<details><summary>Preview</summary>

<img width="1887" height="471" alt="cap" src="https://github.com/user-attachments/assets/2c4de5e8-6b59-4db1-a6d5-6038048945e1" />

TODO: add gif

</details>

<details><summary>Motivation</summary>

`kubectl` is a very useful tool.

While iterating on new services in Kubernetes, though, its verbosity
adds a noticeable "navigation" cost to inspecting the state of the cluster.
This is especially apparent when drilling into problems that a service may be experiencing.

Shell aliases help ([I have many](https://github.com/Iron-E/dotfiles/blob/594b9a383be9907ba3fcee7f333fca32cc277681/home-manager/hosts/_extras_/programs%2Bservices/ctl/kubectl/shell.nix)),
but do little when inspecting resources that have dynamic names (e.g. `Pod`s attached to `ReplicaSet`s).

A shell's autocomplete could then, in theory, further reduce the navigation cost.
However, a slow connection to the cluster will end up adding more to the navigation
cost than it saves.

[k9s] is a good solution to this problem, however, [its issues with MFA](https://github.com/derailed/k9s/issues/2048)
prevent those in many corporate environments from using it.

After seeing what `fzf` could do via [`fzf-lua`](https://github.com/ibhagwan/fzf-lua),
the idea for a new Kubernetes TUI, powered by `fzf` arose.

</details>

<details><summary>Goals</summary>

`kzf` is not a replacement or substitute for `kubectl`.

This project aims to optimize the processes of:

- inspecting the current state of resources in a cluster.
- comparing the state of resources across `--context`s and `--namespace`s.

This project does not aim to be a substitute/replacement for:

- `kubectl`

	Not all features of `kubectl` will be implemented.

	`kubectl` features unrelated to resource inspection/debugging
	(or those which are difficult/unfit to implement with `fzf`)
	are unlikely to be implemented.

	The following is an inexhaustive list of unsupported features:

	- Non-resource inspection: `annotate`, `apply`, `auth`, `diff`, `explain`, `kustomize`, `label`, `replace`, `scale`, `taint`
	- Difficult interface (PR welcome): `debug`, `port-forward`
- An observability stack.

	`kzf` provides no special mechanism to show how the history of a cluster contributed to its current state.

</details>

## Features

- Attaching to containers
- Colors (via [`kubecolor`])
- Deleting resources (w/ confirmation)
- Describing resources
- Executing commands in containers
- Fuzzy selection (via [`fzf`])
- Restarting rollouts
- Showing resource YAML
- Switching contexts & namespaces
- Viewing logs
- Watching resources (live views)

## Installation

### Manual

**Requirements:**

- [`bash`]
- [`curl`]
- [`fzf`]
- [`getopt`][util-linux]
- [`kubectl`]
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
> - [`kubecolor`]
> - [`tspin`] (tailspin)
> - [`viddy`]
> - [`zellij`]

See `kzf -h` for help information, and press F1 while inside `kzf` to see a list of keyboard shortcuts.

## Configuration

There is no built-in configuration mechanism for `kzf`. Instead, one may use e.g. aliases.

## Contributing

The [nix flake](./flake.nix) contains a developer environment.
This environment configures pre-commit hooks and vendors dev dependencies.

Please try to use it when contributing to the project.

## Similar Projects

- [`k9s`]
- [`kdash`]

[`bash`]: https://cgit.git.savannah.gnu.org/cgit/bash.git/
[`curl`]: https://curl.se/
[`fzf`]: https://github.com/junegunn/fzf
[`k9s`]: https://github.com/derailed/k9s
[`kdash`]: https://github.com/kdash-rs/kdash
[`kubecolor`]: https://github.com/kubecolor/kubecolor
[`kubectl`]: https://kubernetes.io/docs/tasks/tools/
[`tspin`]: https://github.com/bensadeh/tailspin
[`viddy`]: https://github.com/sachaos/viddy
[`zellij`]: https://github.com/zellij-org/zellij
[util-linux]: https://github.com/util-linux/util-linux
