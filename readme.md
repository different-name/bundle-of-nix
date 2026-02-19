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

## When to use bundle

**bundle** is extensible and makes as little assumptions about how you like to do things as possible. This allows **bundle** to work well with:

- Single host, single user configs
- Multi host, multi user configs
- Option based pattern
- The dendritic pattern (import based config)
- Pure NixOS configs (i'm not sure why you're here)
- Everything in one file! (please don't)

But if you don't like grouping up configuration from different platforms, **bundle** is not for you

Bundle also does not currently support separate home platform builds, this means no `homeConfigurations`. Though this may be added soon

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

    nero = {
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

Then add your configuration for each user, here's an example configuration:

```nix
{
  bundle = {
    hosts = { ... };

    users = {
      diffy = {
        shared = {
          imports = [ ./users/diffy/shared ];
          home-manager.home.username = "diffy";
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

      nero = { ... };
    };
  };
}
```

Based on your configuration, **bundle** will generate your hosts' configurations for you
