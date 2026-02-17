{
  lib,
  inputs,
  self,
  ...
}:
let
  inherit (lib) types;

  getInput = name: inputs.${name} or (throw "No ${name} input found");

  nixpkgs = getInput "nixpkgs";
  nix-darwin = getInput "nix-darwin";
  home-manager = inputs.home-manager or (throw "No home-manager input found");
  hjem = inputs.hjem or (throw "No hjem input found");

  specialArgs = _: { inherit inputs self; };
  primeArgsConfig =
    { inputs', self', ... }:
    {
      _module.args = { inherit inputs' self'; };
    };
in
{
  options.bundle = {
    systemClasses = lib.mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              namespace = lib.mkOption {
                type = types.str;
                default = name;
                # TODO documentation
              };

              flakeAttribute = lib.mkOption {
                type = types.str;
                # TODO documentation
              };

              mkSystem = lib.mkOption {
                type = types.raw;
                # TODO documentation
              };

              specialArgs = lib.mkOption {
                type = types.raw;
                default = _: { };
                # TODO documentation
              };

              extraConfig = lib.mkOption {
                type = types.raw;
                default = _: { };
                # TODO documentation
              };
            };
          }
        )
      );
      default = { };
      # TODO documentation
    };

    homeClasses = lib.mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, config, ... }:
          {
            options = {
              namespace = lib.mkOption {
                type = types.str;
                default = name;
                # TODO documentation
              };

              system = {
                usersAttrPath = lib.mkOption {
                  type = types.listOf types.str;
                  # TODO documentation
                };

                extraConfig = lib.mkOption {
                  type = types.raw;
                  default = _: { };
                  # TODO documentation
                };

                classes = lib.mkOption {
                  type = types.attrsOf (
                    types.submodule {
                      options = {
                        module = lib.mkOption {
                          type = types.deferredModule;
                          # TODO documentation
                        };

                        usersAttrPath = lib.mkOption {
                          type = types.listOf types.str;
                          default = config.system.usersAttrPath;
                          # TODO documentation
                        };

                        extraConfig = lib.mkOption {
                          type = types.raw;
                          default = config.system.extraConfig;
                          # TODO documentation
                        };
                      };
                    }
                  );
                  # TODO documentation
                };
              };

              extraHomeConfig = lib.mkOption {
                type = types.raw;
                default = _: { };
                # TODO documentation
              };
            };
          }
        )
      );
      default = { };
      # TODO documentation
    };
  };

  config.bundle = {
    systemClasses = {
      nixos = {
        mkSystem = nixpkgs.lib.nixosSystem;
        inherit specialArgs;
        extraConfig = primeArgsConfig;
        flakeAttribute = "nixosConfigurations";
      };

      darwin = {
        mkSystem = nix-darwin.lib.darwinSystem;
        inherit specialArgs;
        extraConfig = primeArgsConfig;
        flakeAttribute = "darwinConfigurations";
      };
    };

    homeClasses = {
      home-manager = {
        system = {
          usersAttrPath = [
            "home-manager"
            "users"
          ];

          extraConfig = _: {
            home-manager.extraSpecialArgs = { inherit inputs self; };
          };

          classes = {
            nixos.module = home-manager.nixosModules.default;
            darwin.module = home-manager.darwinModules.default;
          };
        };

        extraHomeConfig = primeArgsConfig;
      };

      hjem = {
        system = {
          usersAttrPath = [
            "hjem"
            "users"
          ];

          extraConfig = _: { hjem = { inherit specialArgs; }; };

          classes = {
            nixos.module = hjem.nixosModules.default;
            darwin.module = hjem.darwinModules.default;
          };
        };

        extraHomeConfig = primeArgsConfig;
      };
    };
  };
}
