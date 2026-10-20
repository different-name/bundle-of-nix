_:
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
  home-manager = getInput "home-manager";
  hjem = getInput "hjem";

  specialArgs = _: { inherit inputs self; };

  sysExtraConfig =
    {
      inputs',
      self',
      system,
      ...
    }:
    {
      _module.args = { inherit inputs' self'; };
      nixpkgs.hostPlatform = lib.mkDefault system;
    };
  homeExtraConfig = { inputs', self', ... }: {
    _module.args = { inherit inputs' self'; };
  };
in
{
  options.bundle = {
    systemPlatforms = lib.mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              namespace = lib.mkOption {
                type = types.str;
                default = name;
                description = "Attribute to namespace configuration for this platform under";
                example = "nixos";
              };

              flakeAttribute = lib.mkOption {
                type = types.str;
                description = "Attribute configurations for this platform should be placed under";
                example = "nixosConfigurations";
              };

              mkSystem = lib.mkOption {
                type = types.raw;
                description = "Function to use to create the system configuration";
                example = lib.literalExpression "inputs.nixpkgs.lib.nixosSystem";
              };

              specialArgs = lib.mkOption {
                type = types.raw;
                default = _: { };
                description = ''
                  Function to generate specialArgs for this platform

                  Arguments passed are the same as flake-part's withSystem, with the addition of `host`
                '';
                example = lib.literalExpression ''
                  { inputs, inputs', self, self', ... }:
                  {
                    inherit inputs inputs' self self';
                  }
                '';
              };

              extraConfig = lib.mkOption {
                type = types.functionTo types.deferredModule;
                default = _: { };
                description = ''
                  Function to generate a system-level configuration module for this platform

                  Arguments passed are the same as flake-part's withSystem, with the addition of `host`
                '';
                example = lib.literalExpression ''
                  { host, ... }:
                  {
                    networking.hostName = lib.mkDefault host;
                  };
                '';
              };
            };
          }
        )
      );
      default = { };
      description = "Definition for system platforms, for example: nixos or darwin";
    };

    homePlatforms =
      let
        usersAttrPathOption = {
          type = types.listOf types.str;
          description = "The attribute path from system config to per-user config for this platform";
          example = lib.literalExpression ''
            [ "home-manager" "users" ]
          '';
        };

        extraConfigOption = {
          type = types.functionTo types.deferredModule;
          default = _: { };
          description = ''
            Function to generate a system-level configuration module for this platform

            Arguments passed are the same as flake-part's withSystem, with the addition of `host`
          '';
          example = lib.literalExpression ''
            { inputs, inputs', self, self', ... }:
            {
              home-manager.extraSpecialArgs = { inherit inputs inputs' self self'; };
            }
          '';
        };
      in
      lib.mkOption {
        type = types.attrsOf (
          types.submodule (
            { name, config, ... }:
            {
              options = {
                namespace = lib.mkOption {
                  type = types.str;
                  default = name;
                  description = "Attribute to namespace configuration for this platform under";
                };

                usersAttrPath = lib.mkOption usersAttrPathOption;
                extraConfig = lib.mkOption extraConfigOption;

                attachTo = lib.mkOption {
                  type = types.attrsOf (
                    types.submodule {
                      options = {
                        module = lib.mkOption {
                          type = types.deferredModule;
                          description = "The system module to import for this home-platform";
                          example = lib.literalExpression "inputs.home-manager.nixosModules.default";
                        };

                        usersAttrPath = lib.mkOption (usersAttrPathOption // { default = config.usersAttrPath; });
                        extraConfig = lib.mkOption (extraConfigOption // { default = config.extraConfig; });
                      };
                    }
                  );
                  default = { };
                  description = "The system-platforms this home-platform can attach to";
                };

                extraHomeConfig = lib.mkOption {
                  type = types.functionTo types.deferredModule;
                  default = _: { };
                  description = ''
                    Function to generate a home-level configuration module for this platform

                    Arguments passed are the same as flake-part's withSystem, with the addition of `host` and `user`
                  '';
                  example = lib.literalExpression ''
                    { user, ... }:
                    {
                      home = {
                        username = lib.mkDefault user;
                        homeDirectory = lib.mkDefault "/home/''${user}";
                      };
                    }
                  '';
                };

                standalone = lib.mkOption {
                  type = types.nullOr (
                    types.submodule {
                      options = {
                        flakeAttribute = lib.mkOption {
                          type = types.str;
                          description = "Attribute standalone home configurations for this platform should be placed under";
                          example = "homeConfigurations";
                        };

                        mkSystem = lib.mkOption {
                          type = types.raw;
                          description = "Function to create a standalone home configuration, called with `{ pkgs, specialArgs, modules }`";
                          example = lib.literalExpression "inputs.home-manager.lib.homeManagerConfiguration";
                        };

                        specialArgs = lib.mkOption {
                          type = types.raw;
                          default = _: { };
                          description = ''
                            Function to generate specialArgs for a standalone home configuration

                            Arguments passed are the same as flake-part's withSystem, with the addition of `host` and `user`
                          '';
                        };
                      };
                    }
                  );
                  default = null;
                  description = "How to build this home-platform standalone, for system-less hosts. When null, this home-platform can only be used embedded in a system";
                };
              };
            }
          )
        );
        default = { };
        description = "Definition for home platforms, for example: home-manager or hjem";
      };
  };

  config.bundle = {
    systemPlatforms = {
      nixos = {
        mkSystem = nixpkgs.lib.nixosSystem;
        inherit specialArgs;
        extraConfig = sysExtraConfig;
        flakeAttribute = "nixosConfigurations";
      };

      darwin = {
        mkSystem = nix-darwin.lib.darwinSystem;
        inherit specialArgs;
        extraConfig = sysExtraConfig;
        flakeAttribute = "darwinConfigurations";
      };
    };

    homePlatforms = {
      home-manager = {
        usersAttrPath = [
          "home-manager"
          "users"
        ];

        extraConfig = _: {
          home-manager.extraSpecialArgs = { inherit inputs self; };
        };

        attachTo = {
          nixos.module = home-manager.nixosModules.default;
          darwin.module = home-manager.darwinModules.default;
        };

        extraHomeConfig =
          args@{ user, ... }:
          (homeExtraConfig args)
          // {
            home.username = lib.mkOptionDefault user;
          };

        standalone = {
          flakeAttribute = "homeConfigurations";
          specialArgs = _: { inherit inputs self; };
          mkSystem =
            {
              pkgs,
              specialArgs,
              modules,
            }:
            home-manager.lib.homeManagerConfiguration {
              inherit pkgs modules;
              extraSpecialArgs = specialArgs;
            };
        };
      };

      hjem = {
        usersAttrPath = [
          "hjem"
          "users"
        ];

        extraConfig = _: { hjem = { inherit specialArgs; }; };

        attachTo = {
          nixos.module = hjem.nixosModules.default;
          darwin.module = hjem.darwinModules.default;
        };

        extraHomeConfig = homeExtraConfig;
      };
    };
  };
}
