# bundle

bundle your nixos, darwin, home-manager, hjem & other class configuration together!

just look how nice it is to merge your configurations together :)

```nix
{
  lib,
  config,
  inputs',
  self,
  ...
}:
{
  options.dyad.desktop.hyprland.enable = lib.mkEnableOption "Hyprland config";

  config = lib.mkIf config.dyad.desktop.hyprland.enable {
    nixos = {
      programs.hyprland = {
        enable = true;
        package = inputs'.hyprland.packages.hyprland;
        portalPackage = inputs'.hyprland.packages.xdg-desktop-portal-hyprland;
      };
    };

    home-manager = {
      imports = [
        self.homeModules.xdgDesktopPortalHyprland
      ];

      config = {
        wayland.windowManager.hyprland = {
          enable = true;
          package = null;
          portalPackage = null;

          xwayland.enable = true;
        };

        services.hyprpolkitagent.enable = true;
      };
    };
  };
}
```

- class agnostic and easily extensible to any other classes
- fully configurable
- user centric
- many to many user & host support

early work in progress! options are subject to change (or break)