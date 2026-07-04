# bundle

The coziest way to manage your nix config!

**bundle** is a [flake-parts](https://flake.parts/) module that groups your configuration into small, feature-focused modules called **bundles**. Each bundle can contain bits of config for multiple system platforms, such as NixOS and Darwin, and multiple home platforms, such as Home Manager and Hjem

#### Contents

- [The problem](#the-problem)
- [The solution](#the-solution-bundle)
- [When to use bundle](#when-to-use-bundle)
- [User-centric configuration](#user-centric-configuration)
- [Supported platforms](#supported-platforms)
- [Getting started](#getting-started)

## The problem

Most (non **bundle**) configurations are typically platform focused, splitting up configuration files by platform:

```
darwin
├── fish.nix
└── hyprland.nix
home-manager
├── fish.nix
├── hyprland.nix
├── librewolf.nix
└── obs-studio.nix
nixos
├── fish.nix
├── hyprland.nix
└── obs-studio.nix
```

## The solution (bundle)

**bundle** unites your platforms under a single module system, giving you far more flexibility for whatever structure you want to use:

```
applications
├── librewolf.nix
└── obs-studio.nix
desktop
└── hyprland.nix
terminal
└── fish.nix
```

Here's a look at that OBS module, we're able to apply both nixos and home-manager configuration in one place

```nix
{
  nixos.programs.obs-studio = {
    enable = true;
    enableVirtualCamera = true;
  };

  home-manager = { pkgs, ... }: {
    programs.obs-studio = {
      enable = true;
      plugins = [ pkgs.obs-studio-plugins.obs-move-transition ];
    };
  };
}
```

You could even wrap it with an enable option if you'd like to

```nix
{ lib, config, ... }:
{
  options.myConfig.applications.obs-studio.enable = lib.mkEnableOption "obs-studio config";

  config = lib.mkIf config.myConfig.applications.obs-studio.enable {
    nixos = { ... };
    home-manager = { ... };
  };
}
```

Bundle modules receive `bundleLib`, whose `mkEnableModule` is a shorthand for this pattern:

```nix
{ bundleLib, ... }:
bundleLib.mkEnableModule [ "myConfig" "applications" "obs-studio" ] {
  nixos = { ... };
  home-manager = { ... };
}
```

## When to use bundle

**bundle** is extensible and makes as little assumptions about how you like to do things as possible. This allows **bundle** to work well with:

- Single host, single user configs
- Multi host, multi user configs
- Option based pattern
- The dendritic pattern (import based config)
- Pure NixOS configs (i'm not sure why you're here)
- Everything in one file! (please don't)

But if you don't like grouping up configuration from different platforms, **bundle** is not for you

Standalone home builds (like `homeConfigurations` for a non-NixOS machine) are supported through system-less hosts, see [Standalone home configurations](#standalone-home-configurations)

## User-centric configuration

In **bundle**, hosts are configured in the context of a user. This means configuration cannot be applied directly to a host:

```nix
{
  bundle.users = {
    diffy = {
      shared = { ... };
      hosts = {
        sodium = { ... };
        potassium = { ... };
      };
    };

    alice = {
      shared = { ... };
      hosts = {
        potassium = { ... };
        iodine = { ... };
      };
    };
  };
}
```

If a host is shared between multiple users, it will inherit configuration from both of those users

User-centric configuration like this allows for per user configuration (home-manager, etc) to be included in bundles, while maintaining multi-user support

## Supported platforms

**bundle** is platform agnostic & extensible through the [`systemPlatforms` & `homePlatforms`](module/platforms.nix) options, this means you can extend **bundle** to work with any system or home platform you'd like

Some platforms are configured by default, if a platform you want to use isn't included here, feel free to make an issue:

### Default system platforms

- [NixOS](https://github.com/NixOS/nixpkgs)
- Darwin ([nix-darwin](https://github.com/nix-darwin/nix-darwin))

### Default home platforms

- [Home Manager](https://github.com/nix-community/home-manager)
- [hjem](https://github.com/feel-co/hjem)

**bundle** has no flake inputs of its own and reads them from your flake. Each default platform needs the input of the same name, only when that platform is used:

| Input | Required when |
| --- | --- |
| `nixpkgs` | using the `nixos` system platform, or any system-less host |
| `nix-darwin` | using the `darwin` system platform |
| `home-manager` | using the `home-manager` home platform |
| `hjem` | using the `hjem` home platform |

## Getting started

Firstly, configure the `system` & `systemPlatform` for each of your hosts:

```nix
{
  bundle = {
    hosts = {
      sodium = {
        system = "x86_64-linux";
        systemPlatform = "nixos";
      };
      potassium = {
        system = "x86_64-darwin";
        systemPlatform = "darwin";
      };
      iodine = {
        system = "x86_64-linux";
        systemPlatform = "nixos";
      };
    };
  };
}
```

The `nixos` and `darwin` platforms set `nixpkgs.hostPlatform` from the host's `system` with `mkDefault`.

Then add your configuration for each user, here's an example configuration:

```nix
{
  bundle = {
    hosts = { ... };

    users = {
      diffy = {
        shared = {
          imports = [ ./users/diffy/shared ];
        };
        hosts = {
          sodium = {
            imports = [ ./users/diffy/hosts/sodium ];
            nixos.networking.hostName = "sodium";
          };
          potassium = {
            imports = [ ./users/diffy/hosts/sodium ];
            nixos.networking.hostName = "potassium";
          };
        };
      };

      alice = { ... };
    };
  };
}
```

Based on your configuration, **bundle** will generate your hosts' configurations for you

## Standalone home configurations

To manage home config on a machine that isn't NixOS or Darwin (a foreign distro, WSL, a server), declare a host with no `systemPlatform`:

```nix
{
  bundle = {
    hosts.workbox.system = "x86_64-linux";

    users.diffy = {
      shared.imports = [ ./users/diffy/shared ];
      hosts.workbox.imports = [ ./users/diffy/hosts/workbox ];
    };
  };
}
```

The host builds no system. Each of its users with config for a home-platform that has a standalone builder (`home-manager` by default) gets a build under that platform's `flakeAttribute`, named `<user>@<host>`:

```sh
home-manager switch --flake .#"diffy@workbox"
```

`home.username` defaults to the user's name. `home.homeDirectory` still has to be set.

A host builds either a system or standalone home configurations. Home config for a home-platform without a standalone builder, such as `hjem`, is an error on a system-less host.
